#!/usr/bin/env python3
"""Shared, event-driven Hyprland brightness controller (Python standard library).

Shell entry points retain the existing key bindings. Waybar subscribes to one
session-local Unix socket; only this process reads topology and writes hardware.
"""
import argparse
import asyncio
from dataclasses import dataclass
import fcntl
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import concurrent.futures
import ctypes
import threading


class DDC:
    """External monitors through libddcutil, the display held open for one ramp: a write
    takes ~70 ms instead of ~300 ms for a fresh `ddcutil` process, quick enough
    to ramp brightness in small eased steps, the way a laptop backlight fades.
    One worker thread owns every handle (libddcutil ties a handle to the thread
    that opened it). Any failure → None, and the caller falls back to ddcutil."""

    def __init__(self):
        self.lib = None
        self.handles = {}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix='ddc')
        try:
            lib = ctypes.CDLL('libddcutil.so.5')
            lib.ddca_init2.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
            lib.ddca_set_sleep_multiplier.argtypes = [ctypes.c_double]
            lib.ddca_create_busno_display_identifier.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)]
            lib.ddca_get_display_ref.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
            lib.ddca_open_display2.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.POINTER(ctypes.c_void_p)]
            lib.ddca_close_display.argtypes = [ctypes.c_void_p]
            lib.ddca_set_non_table_vcp_value.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint8]
            self.lib = lib
            self.pool.submit(self._init).result(timeout=10)
        except Exception:
            self.lib = None

    def _init(self):
        if self.lib.ddca_init2(None, 0, 0, None) != 0:
            self.lib = None
            return
        self.lib.ddca_set_sleep_multiplier(0.2)

    def _handle(self, bus):
        h = self.handles.get(bus)
        if h:
            return h
        did, ref, dh = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
        if (self.lib.ddca_create_busno_display_identifier(bus, ctypes.byref(did)) or
                self.lib.ddca_get_display_ref(did, ctypes.byref(ref)) or
                self.lib.ddca_open_display2(ref, True, ctypes.byref(dh))):
            return None
        self.handles[bus] = dh
        return dh

    def _set(self, bus, raw):
        h = self._handle(bus)
        if not h:
            return False
        if self.lib.ddca_set_non_table_vcp_value(h, 0x10, (raw >> 8) & 0xff, raw & 0xff) == 0:
            return True
        # A stale handle (the monitor slept or was replugged): reopen once.
        self.lib.ddca_close_display(h)
        self.handles.pop(bus, None)
        h = self._handle(bus)
        return bool(h) and self.lib.ddca_set_non_table_vcp_value(h, 0x10, (raw >> 8) & 0xff, raw & 0xff) == 0

    def _release(self, bus):
        h = self.handles.pop(bus, None)
        if h:
            self.lib.ddca_close_display(h)

    async def release(self, bus):
        """Close the display after a ramp: an open handle holds ddcutil's bus
        lock, and every other ddcutil user (this service's own reads, other
        tools) would wait on it."""
        if self.lib:
            try:
                await asyncio.get_running_loop().run_in_executor(self.pool, self._release, bus)
            except Exception:
                pass

    async def set(self, bus, raw):
        if not self.lib:
            return False
        try:
            return await asyncio.get_running_loop().run_in_executor(self.pool, self._set, bus, raw)
        except Exception:
            return False


def build_modules(names):
    """One GTK event target per connector; no fixed monitor count or text hit-test."""
    names = sorted(set(names), key=lambda name: (not internal(name), name))
    command = '"$HOME/Scripts/brightness.sh"'
    def module(part, output=None):
        # Waybar exports WAYBAR_OUTPUT_NAME to exec only, not to click/scroll
        # handlers, so the main chip resolves its screen from the cursor.
        target = f' --output {shlex.quote(output)}' if output else ' --at-cursor'
        bar = '' if output else ' --output "${WAYBAR_OUTPUT_NAME:-}"'
        return {'exec': f'{command} watch --part {shlex.quote(part)}{bar}',
                'return-type': 'json', 'restart-interval': 2,
                'exec-on-event': False, 'hide-empty-text': True,
                'format': '{}', 'escape': False, 'tooltip': True,
                'smooth-scrolling-threshold': 2,
                'on-click': f'{command} preset{target}',
                'on-click-right': f'{command} view',
                'on-click-middle': f'{command} refresh',
                'on-scroll-up': f'{command} up{target}',
                'on-scroll-down': f'{command} down{target}'}
    data = {'__brightness_managed': True, 'custom/brightness': module('main')}
    modules = ['custom/brightness']
    for name in names:
        key = 'custom/brightness-output-' + hashlib.sha256(name.encode()).hexdigest()[:12]
        modules.append(key)
        data[key] = module(name, name)
    data['group/brightness'] = {'orientation': 'inherit', 'modules': modules}
    return data


OSD_ICONS = Path.home() / '.local/share/brightness-osd'


def internal(name):
    return name.startswith(('eDP-', 'LVDS-', 'DSI-'))


def level_icon(value):
    if value is None:
        return '󰃞'
    return '󰃞' if value < 34 else '󰃟' if value < 67 else '󰃠'


def next_value(current, up, is_internal):
    # One curve for every screen: fine 1% steps at the dim end (where 5% is
    # a big jump to the eye), then the 5% grid so 41 goes to 45/40 instead of
    # drifting through 46, 51, ... (Monitors used to step 5% all the way down.)
    if current < 10 if up else current <= 10:
        value = current + (1 if up else -1)
    else:
        value = (current // 5 + 1) * 5 if up else (-(-current // 5) - 1) * 5
    return max(1 if is_internal else 0, min(100, value))


def hypr_socket(name):
    return (Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'hypr'
            / os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '') / name)


def parse_detect(text):
    result = {}
    valid, bus = False, None
    for line in text.splitlines():
        if line.startswith(('Display ', 'Invalid display')):
            valid, bus = line.startswith('Display '), None
        elif valid and 'I2C bus:' in line:
            match = re.search(r'/dev/i2c-(\d+)', line)
            bus = int(match[1]) if match else None
        elif valid and 'DRM connector:' in line and bus is not None:
            name = line.split(':', 1)[1].strip()
            result[re.sub(r'^card\d+-', '', name)] = bus
    return result


def parse_vcp(text):
    match = re.search(r'^VCP 10 C (\d+) (\d+)\s*$', text, re.M)
    if not match or int(match[2]) <= 0:
        raise ValueError('Brightness value unavailable from DDC/CI')
    value, maximum = map(int, match.groups())
    return min(100, round(value * 100 / maximum)), maximum


@dataclass
class Output:
    name: str
    value: int | None = None
    maximum: int = 100
    desired: int | None = None
    bus: int | None = None
    device: Path | None = None
    error: str = ''
    revision: int = 0


class Controller:
    def __init__(self, runtime):
        self.runtime = runtime
        self.monitors = []
        self.focus = ''
        self.outputs = {}
        self.workers = {}
        self.subscribers = {}
        self.last_payloads = {}
        self.module_file = None
        self.reload_task = None
        self.show_all = False
        self.ready = asyncio.Event()
        self.topology_lock = asyncio.Lock()
        self.sync_lock = asyncio.Lock()
        self.focus_revision = 0
        self.initializing = None
        self.online = True
        self.notice = None
        self.notice_task = None
        self.osd_queues = set()
        self.ddc = DDC()

    async def run(self, *args, timeout=5):
        try:
            p = await asyncio.create_subprocess_exec(
                *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                start_new_session=True)
        except OSError as exc:
            raise RuntimeError(f'{args[0]} unavailable: {exc.strerror}') from exc
        try:
            stdout, stderr = await asyncio.wait_for(p.communicate(), timeout)
        except (TimeoutError, asyncio.CancelledError):
            if p.returncode is None:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            await p.wait()
            raise
        if p.returncode:
            error = stderr.decode(errors='replace').strip().splitlines()
            raise RuntimeError((error[-1] if error else f'{args[0]} failed')[:180])
        return stdout.decode(errors='replace')

    def target(self, name=None):
        connected = [m['name'] for m in self.monitors]
        if not connected or not self.online:
            raise ValueError('No connected display or Hyprland IPC unavailable')
        selected = name or (self.focus if self.focus in connected else connected[0])
        if selected not in connected:
            raise ValueError(f'Display disconnected: {selected}')
        return self.outputs[selected]

    def read_backlight(self, output):
        if output.device is None:
            raise ValueError('No backlight device for this display')
        maximum = int((output.device / 'max_brightness').read_text())
        actual = output.device / 'actual_brightness'
        value = int((actual if actual.exists() else output.device / 'brightness').read_text())
        output.maximum = maximum
        output.value = round(value * 100 / maximum)

    def label(self, name):
        if internal(name):
            return 'Laptop'
        return next((m.get('model') for m in self.monitors if m['name'] == name and m.get('model')), name)

    def chip(self, o, icon):
        # Fixed-width number and no pending marker in the text: the bar must not
        # reflow on every step. Pending/error state is carried by CSS classes.
        value = o.desired if o.desired is not None else o.value
        text = f'{icon} {value:>2}%' if value is not None else f'{icon} —'
        return text + ' !' if o.error else text

    def classes(self, o):
        classes = ['internal' if internal(o.name) else 'external']
        if o.desired is not None:
            classes.append('brightness-pending')
        if o.error:
            classes.append('brightness-error')
        return classes

    def render(self, output=None):
        try:
            shown = self.target(output if output in self.outputs else None)
        except ValueError as exc:
            return {'text': '󰃞 —', 'tooltip': str(exc), 'class': ['brightness-unavailable']}
        lines = []
        for monitor in self.monitors:
            o = self.outputs[monitor['name']]
            value = o.desired if o.desired is not None else o.value
            notes = [n for n, on in (('this bar', o is shown and output is not None),
                                     ('brightness keys', o.name == self.focus)) if on]
            if o.error:
                notes.append(o.error)
            suffix = f'  ({", ".join(notes)})' if notes else ''
            lines.append(html.escape(f'{self.label(o.name)}: {value if value is not None else "unknown"}%{suffix}'))
        lines += ['', 'Scroll: adjust this screen',
                  'Click: presets · Right-click: show all screens',
                  'Middle-click: re-detect displays',
                  'Brightness keys follow the focused screen']
        value = shown.desired if shown.desired is not None else shown.value
        return {'text': self.chip(shown, level_icon(value)), 'tooltip': '\n'.join(lines),
                'class': self.classes(shown)}

    def render_part(self, part=None, output=None):
        data = self.render(output)
        if part is None:
            return data  # Backwards-compatible diagnostic stream.
        if part == 'main':
            if self.show_all and self.online and self.monitors:
                data = dict(data, text='󰃠')
            return data
        if not self.show_all or not self.online or part not in self.outputs:
            return {'text': '', 'tooltip': '', 'class': []}
        o = self.outputs[part]
        chip = self.chip(o, '󰌢' if internal(part) else '󰍹')
        if part == self.focus:
            chip = f'<b>{chip}</b>'
        return {'text': chip, 'tooltip': html.escape(f'{self.label(part)} · scroll adjusts this screen')+'\n\n'+data['tooltip'],
                'class': self.classes(o)}

    def publish(self):
        for queue, (part, output) in self.subscribers.items():
            data = self.render_part(part, output)
            if self.last_payloads.get(queue) == data:
                continue
            self.last_payloads[queue] = data
            if queue.full():
                queue.get_nowait()
            queue.put_nowait(data)

    async def update_modules(self):
        if self.module_file is None:
            return
        try:
            previous = json.loads(self.module_file.read_text())
            if previous.get('__brightness_managed') is not True:
                raise ValueError('Refusing to overwrite unowned brightness module file')
            data = build_modules([m['name'] for m in self.monitors])
            if previous == data:
                return
            fd, temporary = tempfile.mkstemp(prefix='.brightness-', dir=self.module_file.parent)
            try:
                with os.fdopen(fd, 'w') as stream:
                    json.dump(data, stream, indent=2)
                    stream.write('\n')
                os.replace(temporary, self.module_file)
            finally:
                Path(temporary).unlink(missing_ok=True)
            if self.reload_task:
                self.reload_task.cancel()
            async def reload_bar():
                await asyncio.sleep(.2)  # Coalesce connector event bursts.
                try:
                    await self.run('pkill', '-USR2', '-u', str(os.getuid()), '-x', 'waybar', timeout=2)
                except (RuntimeError, TimeoutError):
                    pass
            self.reload_task = asyncio.create_task(reload_bar())
        except (OSError, ValueError) as exc:
            print(f'Brightness modules: {exc}', file=sys.stderr)

    def queue_notify(self, name, error=None, limit=False):
        # Feedback shows the requested value immediately instead of waiting for
        # a slow DDC write. A running glass HUD (~/.config/quickshell/glass-osd)
        # gets an event on its `watch --part osd` stream; dunst is the fallback.
        o = self.outputs.get(name)
        if self.osd_queues and o is not None:
            event = {'kind': 'brightness', 'output': name, 'internal': internal(name),
                     'label': 'Built-in Display' if internal(name) else self.label(name),
                     'value': o.desired if o.desired is not None else o.value,
                     'error': error or '', 'limit': limit}
            for queue in self.osd_queues:
                if queue.full():
                    queue.get_nowait()
                queue.put_nowait(event)
            return
        # Key repeat collapses into one in-flight notify-send.
        self.notice = (name, error)
        if self.notice_task is None or self.notice_task.done():
            self.notice_task = asyncio.create_task(self.notifier())

    async def notifier(self):
        while self.notice:
            (name, error), self.notice = self.notice, None
            o = self.outputs.get(name)
            if o is None:
                continue
            await self.notify(name, None if error else o.desired if o.desired is not None else o.value, error)

    async def notify(self, name, value=None, error=None):
        # Summary is the display, body the value; the dunst rule in
        # dunstrc.d/50-brightness.conf lays them out as an Apple-style HUD.
        level = 0 if not value else 1 + min(3, value * 4 // 101)
        icon = OSD_ICONS / f'sun-{level}.svg'
        args = ['notify-send', '-a', 'Brightness', '-t', '1500', '-u', 'low',
                '-h', 'string:x-dunst-stack-tag:brightness',
                '-h', 'string:x-canonical-private-synchronous:brightness',
                '-h', 'boolean:transient:true',
                '-i', str(icon) if icon.exists() else 'display-brightness-symbolic']
        label = 'Built-in Display' if internal(name) else self.label(name)
        if value is not None:
            args += ['-h', f'int:value:{value}', html.escape(label), f'{value}%']
        else:
            args += [html.escape(label), html.escape(f'Unavailable · {error or "unknown"}')]
        try:
            await self.run(*args, timeout=2)
        except (RuntimeError, TimeoutError):
            pass  # Notifications are feedback, never a prerequisite for hardware.

    async def initialize_ddc(self):
        async with self.topology_lock:
            external = [o for n, o in self.outputs.items() if not internal(n)]
            if not external:
                return
            try:
                buses = parse_detect(await self.run('ddcutil', 'detect', '--brief', timeout=12))
            except (RuntimeError, TimeoutError) as exc:
                for o in external:
                    o.error = f'DDC discovery failed: {str(exc) or "timed out"}'
                self.publish()
                return
            async def bootstrap(o):
                if self.outputs.get(o.name) is not o:
                    return
                worker = self.workers.get(o.name)
                if o.desired is not None or (worker and not worker.done()):
                    return
                o.bus = buses.get(o.name)
                if o.bus is None:
                    o.error = 'No DDC/CI bus for this connector'
                else:
                    revision = o.revision
                    try:
                        text = await self.run('ddcutil', '--bus', str(o.bus), '--brief', 'getvcp', '10')
                        value, maximum = parse_vcp(text)
                        if self.outputs.get(o.name) is o and o.desired is None and o.revision == revision:
                            o.value, o.maximum, o.error = value, maximum, ''
                    except (RuntimeError, TimeoutError, ValueError) as exc:
                        if self.outputs.get(o.name) is o and o.revision == revision:
                            o.error = f'DDC read failed: {str(exc) or "timed out"}'
                self.publish()
            await asyncio.gather(*(bootstrap(o) for o in external))

    async def sync_topology(self):
        async with self.sync_lock:
            await self._sync_topology()

    async def _sync_topology(self):
        focus_revision = self.focus_revision
        monitors = json.loads(await self.run('hyprctl', '-j', 'monitors', timeout=3))
        monitors = [m for m in monitors if not m.get('disabled')]
        names = {m['name'] for m in monitors}
        previous = {n: (next((m.get('serial', '') for m in self.monitors if m['name'] == n), ''),
                        next((m.get('model', '') for m in self.monitors if m['name'] == n), ''))
                    for n in self.outputs}
        changed = not self.online or names != set(self.outputs) or any(previous.get(m['name']) !=
                    (m.get('serial', ''), m.get('model', '')) for m in monitors)
        for name in set(self.outputs) - names:
            if name in self.workers:
                self.workers[name].cancel()
            del self.outputs[name]
        for m in monitors:
            name = m['name']
            if name not in self.outputs or previous.get(name) != (m.get('serial', ''), m.get('model', '')):
                if name in self.workers:
                    self.workers[name].cancel()
                self.outputs[name] = Output(name)
        if changed:
            # Bus numbers are not output identities. Invalidate them before
            # publishing a new topology, so a key cannot hit a reassigned bus
            # while discovery is still in flight.
            for name, output in self.outputs.items():
                if not internal(name):
                    if name in self.workers:
                        self.workers[name].cancel()
                    output.bus, output.value, output.desired = None, None, None
        self.monitors = monitors
        if self.focus_revision == focus_revision or self.focus not in names:
            self.focus = next((m['name'] for m in monitors if m.get('focused')), monitors[0]['name'] if monitors else '')
        # Laptop backlight is uniquely identifiable here. Multiple internal panels
        # need an explicit device mapping; never guess and adjust the wrong one.
        devices = sorted(Path('/sys/class/backlight').glob('*'))
        internals = [o for n, o in self.outputs.items() if internal(n)]
        for o in internals:
            if len(internals) == 1 and len(devices) == 1:
                o.device = devices[0]
                try:
                    self.read_backlight(o)
                    o.error = ''
                except (OSError, ValueError, ZeroDivisionError) as exc:
                    o.error = f'Backlight read failed: {exc}'
            else:
                o.error = 'Backlight mapping unavailable or ambiguous'
        self.online = True
        await self.update_modules()
        self.ready.set()
        self.publish()
        if changed:
            if self.initializing and not self.initializing.done():
                self.initializing.cancel()
            self.initializing = asyncio.create_task(self.initialize_ddc())

    async def apply(self, output):
        # A worker owns a particular Output object. Hotplug replaces that object;
        # cancellation and identity checks prevent a stale cache from surviving.
        while self.outputs.get(output.name) is output and output.desired is not None:
            desired = output.desired
            try:
                if internal(output.name):
                    await self.run('brightnessctl', '-d', output.device.name, '-q', 'set', f'{desired}%')
                    self.read_backlight(output)
                else:
                    # Ramp in eased 1% steps (at most 8, ~70 ms each), so the
                    # external screen fades like the laptop's backlight. A new
                    # request mid-ramp retargets from wherever it got to.
                    start = output.value if output.value is not None else desired
                    span = desired - start
                    steps = max(1, min(8, abs(span)))
                    ramped = False
                    for i in range(1, steps + 1):
                        if output.desired != desired or self.outputs.get(output.name) is not output:
                            break
                        t = i / steps
                        pct = round(start + span * (1 - (1 - t) ** 3))
                        raw = round(pct * output.maximum / 100)
                        if not await self.ddc.set(output.bus, raw):
                            break
                        ramped = True
                        output.value = pct
                        if i < steps:
                            self.publish()
                    await self.ddc.release(output.bus)
                    if not ramped or (output.desired == desired and output.value != desired):
                        if output.desired == desired:
                            raw = round(desired * output.maximum / 100)
                            await self.run('ddcutil', '--bus', str(output.bus), '--noverify', 'setvcp', '10', str(raw))
                            output.value = round(raw * 100 / output.maximum)
                output.error = ''
            except (RuntimeError, TimeoutError, OSError, ValueError) as exc:
                output.desired = None
                output.error = f'Brightness write failed: {str(exc) or "timed out"}; last known value shown'
                self.publish()
                self.queue_notify(output.name, error='change failed; middle-click the bar to retry')
                return
            if self.outputs.get(output.name) is not output:
                return
            # Clear only the request actually sent. New commands may have arrived
            # during I/O. No process/file read-modify-write race or exit handoff.
            if output.desired == desired:
                output.desired = None
            self.publish()

    async def output_at_cursor(self):
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_unix_connection(str(hypr_socket('.socket.sock'))), 1)
            try:
                writer.write(b'j/cursorpos')
                await writer.drain()
                pos = json.loads(await asyncio.wait_for(reader.read(), 1))
            finally:
                writer.close()
        except (OSError, ValueError, TimeoutError):
            return None  # Fall back to the focused screen.
        for m in self.monitors:
            width, height = m['width'] / m['scale'], m['height'] / m['scale']
            if m.get('transform', 0) % 2:
                width, height = height, width
            if m['x'] <= pos['x'] < m['x'] + width and m['y'] <= pos['y'] < m['y'] + height:
                return m['name']
        return None

    async def command(self, request):
        action = request.get('action')
        if request.get('at') == 'cursor' and not request.get('output'):
            request['output'] = await self.output_at_cursor()
        if action in ('view', 'toggle'):
            self.show_all = not self.show_all
            self.publish()
            return {'ok': True, 'view': 'all' if self.show_all else 'focused'}
        if action == 'status':
            return {'ok': True, 'focused': self.focus, 'view': 'all' if self.show_all else 'focused',
                    'outputs': {n: {'value': o.value, 'pending': o.desired, 'bus': o.bus, 'error': o.error}
                                for n, o in self.outputs.items()}, 'subscribers': len(self.subscribers)}
        if action == 'refresh':
            if self.initializing and not self.initializing.done():
                return {'ok': True, 'refreshing': True}
            await self.sync_topology()
            if not self.initializing or self.initializing.done():
                self.initializing = asyncio.create_task(self.initialize_ddc())
            return {'ok': True, 'refreshing': True}
        if action == 'set' and (type(request.get('value')) is not int or not 0 <= request['value'] <= 100):
            raise ValueError('Brightness must be an integer from 0 to 100')
        if action not in ('up', 'i', 'down', 'd', 'set', 'which'):
            raise ValueError('Unknown brightness command')
        o = self.target(request.get('output'))
        if action == 'which':
            return {'ok': True, 'output': o.name}
        if o.value is None and self.initializing:
            try:
                await asyncio.shield(self.initializing)
            except asyncio.CancelledError:
                if asyncio.current_task().cancelling():
                    raise
                raise ValueError('Display connection changed during discovery; retry the command') from None
            o = self.target(o.name)
        if internal(o.name):
            if o.device is None:
                raise ValueError(o.error or 'Backlight device unavailable')
            if o.desired is None:
                self.read_backlight(o)
        elif o.bus is None or o.value is None:
            raise ValueError(o.error or 'External brightness unavailable; middle-click to retry')
        current = o.desired if o.desired is not None else o.value
        value = request['value'] if action == 'set' else next_value(current, action in ('up', 'i'), internal(o.name))
        if value == current and o.desired is None:
            self.queue_notify(o.name, limit=True)  # At a limit: still show where it is.
            return {'ok': True, 'output': o.name, 'value': value}
        o.desired, o.error = value, ''
        o.revision += 1
        self.publish()
        self.queue_notify(o.name)
        worker = self.workers.get(o.name)
        if worker is None or worker.done():
            self.workers[o.name] = asyncio.create_task(self.apply(o))
        return {'ok': True, 'output': o.name, 'value': value, 'pending': True}

    async def handle(self, reader, writer):
        queue = None
        try:
            request = json.loads(await asyncio.wait_for(reader.readline(), 3))
            await asyncio.wait_for(self.ready.wait(), 6)
            if request.get('action') == 'watch':
                part, output = request.get('part'), request.get('output')
                if not isinstance(part, (str, type(None))) or not isinstance(output, (str, type(None))):
                    raise ValueError('Invalid brightness segment')
                queue = asyncio.Queue(maxsize=1)
                if part == 'osd':
                    self.osd_queues.add(queue)  # Events only; nothing to render.
                else:
                    self.subscribers[queue] = (part, output)
                    data = self.render_part(part, output)
                    self.last_payloads[queue] = data
                    queue.put_nowait(data)
                disconnect = asyncio.create_task(reader.read())
                try:
                    while not disconnect.done():
                        update = asyncio.create_task(queue.get())
                        done, _ = await asyncio.wait([update, disconnect], return_when=asyncio.FIRST_COMPLETED)
                        if update not in done:
                            update.cancel()
                            await asyncio.gather(update, return_exceptions=True)
                            break
                        writer.write((json.dumps(update.result(), ensure_ascii=False) + '\n').encode())
                        await writer.drain()
                finally:
                    disconnect.cancel()
                    await asyncio.gather(disconnect, return_exceptions=True)
            else:
                result = await self.command(request)
                writer.write((json.dumps(result) + '\n').encode())
                await writer.drain()
        except (ValueError, RuntimeError, TimeoutError, OSError, KeyError, TypeError) as exc:
            try:
                writer.write((json.dumps({'ok': False, 'error': str(exc) or 'Timed out'}) + '\n').encode())
                await writer.drain()
            except OSError:
                pass
        finally:
            if queue is not None:
                self.osd_queues.discard(queue)
                self.subscribers.pop(queue, None)
                self.last_payloads.pop(queue, None)
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass  # A bar can exit/reset its socket during a normal reload.

    async def hypr_events(self):
        address = hypr_socket('.socket2.sock')
        while True:
            writer = None
            try:
                reader, writer = await asyncio.open_unix_connection(str(address))
                await self.sync_topology()
                while line := await reader.readline():
                    event, _, value = line.decode(errors='replace').strip().partition('>>')
                    if event == 'focusedmon':
                        focus = value.split(',', 1)[0]
                        if focus in self.outputs and focus != self.focus:
                            self.focus_revision += 1
                            self.focus = focus
                            self.publish()
                    elif event in ('monitoradded', 'monitorremoved', 'configreloaded'):
                        await self.sync_topology()
            except (OSError, RuntimeError, ValueError, TimeoutError):
                pass
            finally:
                if writer:
                    writer.close()
                    await writer.wait_closed()
            self.online = False
            self.ready.set()
            self.publish()
            await asyncio.sleep(2)

    async def backlight_events(self):
        # Passive kernel uevents also catch hypridle dim/restore and changes made
        # by other programs. No timer, brightnessctl read, or extra subprocess.
        try:
            sock = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, 15)
            sock.bind((0, 1))
            sock.setblocking(False)
        except OSError as exc:
            print(f'Backlight event subscription unavailable: {exc}', file=sys.stderr)
            return
        try:
            loop = asyncio.get_running_loop()
            while True:
                event = await loop.sock_recv(sock, 65536)
                if b'SUBSYSTEM=backlight\x00' not in event:
                    continue
                for o in self.outputs.values():
                    if o.device is not None and o.desired is None:
                        try:
                            self.read_backlight(o)
                            o.error = ''
                        except (OSError, ValueError, ZeroDivisionError):
                            continue
                self.publish()
        finally:
            sock.close()


def runtime_dir():
    base = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
    signature = hashlib.sha256(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', 'default').encode()).hexdigest()[:12]
    path = base / f'waybar-brightness-{signature}'
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise RuntimeError('Brightness runtime directory must be private and owned by this user')
    return path


async def serve(runtime):
    with (runtime / 'service.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        address = runtime / 'control.sock'
        address.unlink(missing_ok=True)
        c = Controller(runtime)
        module_file = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'waybar/brightness-monitors.json'
        if module_file.is_file():
            c.module_file = module_file
        server = await asyncio.start_unix_server(c.handle, path=str(address), limit=8192)
        (runtime / 'pid').write_text(str(os.getpid()))
        tasks = [asyncio.create_task(c.hypr_events()), asyncio.create_task(c.backlight_events())]
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stop.set)
        try:
            async with server:
                await stop.wait()
                # Since Python 3.12 leaving the block waits for every client to
                # disconnect; Waybar watchers never do, so drop them explicitly.
                server.close()
                server.close_clients()
        finally:
            for task in tasks + list(c.workers.values()) + ([c.initializing] if c.initializing else []):
                task.cancel()
            for task in (c.reload_task, c.notice_task):
                if task:
                    task.cancel()
            await asyncio.gather(*tasks, *c.workers.values(), *([c.initializing] if c.initializing else []), return_exceptions=True)
            address.unlink(missing_ok=True)
            (runtime / 'pid').unlink(missing_ok=True)


async def client(args, runtime):
    address = str(runtime / 'control.sock')
    try:
        reader, writer = await asyncio.open_unix_connection(address)
    except OSError:
        with (runtime / 'service.log').open('ab') as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--serve'],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                             start_new_session=True, close_fds=True)
        for _ in range(80):
            await asyncio.sleep(0.025)
            try:
                reader, writer = await asyncio.open_unix_connection(address)
                break
            except OSError:
                continue
        else:
            raise RuntimeError(f'Brightness controller did not start; see {runtime}/service.log')
    request = {'action': args.action}
    if args.value is not None:
        try:
            request['value'] = int(args.value)
        except ValueError:
            raise ValueError('Brightness must be an integer from 0 to 100') from None
    if args.output:
        request['output'] = args.output
    writer.write((json.dumps(request) + '\n').encode())
    await writer.drain()
    try:
        while line := await reader.readline():
            result = json.loads(line)
            if result.get('ok') is False:
                raise RuntimeError(result.get('error', 'Brightness request failed'))
            if args.action == 'which':
                print(result['output'])
            elif args.action in ('watch', 'status'):
                print(line.decode().strip(), flush=True)
            if args.action != 'watch':
                return
    finally:
        writer.close()
        await writer.wait_closed()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', default='which', choices=['i', 'd', 'up', 'down', 'set', 'which', 'view', 'toggle', 'watch', 'refresh', 'status'])
    parser.add_argument('value', nargs='?')
    parser.add_argument('--output', help='Explicit connected output for diagnostics; keys follow focus')
    parser.add_argument('--serve', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        asyncio.run(serve(runtime_dir()) if args.serve else client(args, runtime_dir()))
    except (RuntimeError, ValueError, OSError) as exc:
        if args.action == 'watch':
            print(json.dumps({'text': '󰃟 —', 'tooltip': str(exc), 'class': ['brightness-error']}), flush=True)
        else:
            print(f'Brightness: {exc}', file=sys.stderr)
        return 1
    except (KeyboardInterrupt, BrokenPipeError):
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
