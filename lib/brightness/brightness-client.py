#!/usr/bin/env python3
"""Small synchronous socket client; keeps Waybar subscribers lightweight."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time


def runtime_dir():
    signature=hashlib.sha256(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE','default').encode()).hexdigest()[:12]
    path=Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))/f'waybar-brightness-{signature}'
    path.mkdir(mode=0o700,parents=True,exist_ok=True)
    if path.stat().st_uid!=os.getuid() or path.stat().st_mode & 0o077:
        raise RuntimeError('Brightness runtime directory must be private and owned by this user')
    return path


# ── One controller, and it is the session's copy of the code ────────────────
# The controller detaches and outlives whatever started it. Started once from
# a working checkout (a test, a dev session), it kept serving the installed
# desktop's brightness keys with that checkout's code until the next boot
# (found 2026-11-18: 46 hours). And after `kuwai promote` the old code kept
# running the same way. So the controller says which code it is (runtime/owner:
# the file's path and hash), and a client that is the session's copy (it lives
# under KUWAI_ROOT) replaces one that differs. A client from any other checkout
# never replaces anything: it uses the controller that is there.
def code_id(path):
    p=Path(path).resolve()
    try:
        return {'path':str(p),'sha':hashlib.sha256(p.read_bytes()).hexdigest()}
    except OSError:
        return {'path':str(p),'sha':''}


def session_copy(path,root=None):
    root=os.environ.get('KUWAI_ROOT') if root is None else root
    if not root:
        return False
    try:
        return Path(path).resolve().is_relative_to(Path(root).resolve())
    except (OSError,ValueError):
        return False


def stale_daemon(runtime,mine):
    try:
        owner=json.loads((runtime/'owner').read_text())
    except (OSError,ValueError):
        owner=None                       # a controller from before it said: replace it
    return owner!=mine


def stop_daemon(runtime,proc=Path('/proc')):
    """Ask the controller to end (it restores nothing: levels live in the hardware). Only a
    process of yours whose command line is the controller's is ever signalled."""
    try:
        pid=int((runtime/'pid').read_text().strip())
        if (proc/str(pid)).stat().st_uid!=os.getuid():
            return False
        argv=(proc/str(pid)/'cmdline').read_bytes().split(b'\0')
    except (OSError,ValueError):
        return False
    if pid<=1 or b'--serve' not in argv or not any(a.endswith(b'brightness.py') for a in argv):
        return False
    try:
        os.kill(pid,signal.SIGTERM)
    except OSError:
        return False
    for _ in range(120):
        time.sleep(.025)
        try:
            # Gone, or ended and only waiting for its parent to collect it.
            if (proc/str(pid)/'stat').read_text().rsplit(')',1)[1].split()[0]=='Z':
                return True
        except (OSError,IndexError):
            return True
    return False


def connect(runtime):
    daemon=Path(__file__).with_name('brightness.py')
    if (runtime/'pid').exists() and session_copy(daemon) and stale_daemon(runtime,code_id(daemon)):
        stop_daemon(runtime)

    def open_socket():
        sock=socket.socket(socket.AF_UNIX)
        sock.settimeout(25)
        try:
            sock.connect(str(runtime/'control.sock'))
            return sock
        except OSError:
            sock.close()
            raise
    try:
        return open_socket()
    except OSError:
        with (runtime/'service.log').open('ab') as log:
            subprocess.Popen([sys.executable,str(Path(__file__).with_name('brightness.py')),'--serve'],
                             stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True,close_fds=True)
    for _ in range(80):
        time.sleep(.025)
        try:
            return open_socket()
        except OSError:
            pass
    raise RuntimeError(f'Brightness controller did not start; see {runtime}/service.log')


def request(runtime,message):
    with connect(runtime) as sock:
        sock.sendall((json.dumps(message)+'\n').encode())
        with sock.makefile('r') as stream:
            line=stream.readline()
        if not line:
            raise RuntimeError('Brightness controller closed without a reply')
        result=json.loads(line)
        if result.get('ok') is False:
            raise RuntimeError(result.get('error','Brightness request failed'))
        return result


def preset(runtime,output=None,at_cursor=False):
    with (runtime/'menu.lock').open('a') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            return
        status=request(runtime,{'action':'status'})
        output=output or request(runtime,{'action':'which','at':'cursor'} if at_cursor else {'action':'which'})['output']
        if output not in status['outputs']:
            raise ValueError('The selected display is disconnected')
        current=status['outputs'][output]['value']
        choices=[f'Current: {current if current is not None else "unknown"}% (keep)',
                 '5%','10%','25%','50%','75%','100%','Increase 5%','Decrease 5%']
        result=subprocess.run(['rofi','-dmenu','-i','-no-custom','-format','i',
                               '-p',f'Brightness · {output}',
                               '-mesg','Choose a preset · Esc keeps the current brightness',
                               '-theme',os.environ.get('ROFI_MENU_STYLE','clipboard')],
                              input='\n'.join(choices)+'\n',stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL,text=True)
        if result.returncode or not result.stdout.strip():
            return
        try:
            index=int(result.stdout.strip())
        except ValueError:
            return
        if not 0<index<len(choices):
            return
        if index<7:
            message={'action':'set','value':int(choices[index][:-1]),'output':output}
        else:
            message={'action':'up' if index==7 else 'down','output':output}
        request(runtime,message)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',nargs='?',default='which',choices=['i','d','up','down','set','which','view','toggle','watch','refresh','status','preset','socket'])
    parser.add_argument('value',nargs='?',type=int)
    parser.add_argument('--output')
    parser.add_argument('--part')
    parser.add_argument('--at-cursor',action='store_true',help='target the screen under the pointer (Waybar click/scroll)')
    args=parser.parse_args()
    try:
        runtime=runtime_dir()
        if args.action=='preset':
            preset(runtime,args.output,args.at_cursor)
            return 0
        if args.action=='socket':
            # The controller's socket, for a client that holds the stream itself
            # (the shell's HUD): the private directory is checked above and the
            # controller started if it wasn't running.
            with connect(runtime):
                pass
            print(runtime/'control.sock')
            return 0
        message={'action':args.action}
        if args.output:message['output']=args.output
        if args.part:message['part']=args.part
        if args.at_cursor:message['at']='cursor'
        if args.value is not None:message['value']=args.value
        if args.action=='watch':
            with connect(runtime) as sock:
                sock.settimeout(None)
                sock.sendall((json.dumps(message)+'\n').encode())
                with sock.makefile('r') as stream:
                    for line in stream:
                        result=json.loads(line)
                        if result.get('ok') is False:
                            raise RuntimeError(result.get('error','Brightness request failed'))
                        print(line.strip(),flush=True)
        else:
            result=request(runtime,message)
            if args.action=='which':print(result['output'])
            elif args.action=='status':print(json.dumps(result))
        return 0
    except (RuntimeError,ValueError,OSError) as exc:
        if args.action=='watch':
            print(json.dumps({'text':'󰃟 —','tooltip':str(exc),'class':['brightness-error']}),flush=True)
        else:
            print(f'Brightness: {exc}',file=sys.stderr)
        return 1
    except (KeyboardInterrupt,BrokenPipeError):
        return 0


if __name__=='__main__':sys.exit(main())
