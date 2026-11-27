import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
import * as DayNight from '../../shell/services/wallDayNight.mjs';

function controller() {
  const played = [], commands = [];
  const fx = functions('shell/services/WallFx.qml', [
    'onSunSchedule', 'onDayNightReady', 'applyVariantResult',
  ], {
    DayNight,
    Settings: { wallDayNight: true },
    Hyde: { present: false },
    Paths: { bin: '/bin' },
    Quickshell: { execDetached(command) { commands.push(command); } },
    sunBlocked: false, phase: '', queued: null, lastBoundary: '',
    pendingSun: null, preparedSun: null,
    variantProc: { running: false },
    play(path, start, live, outputs, guard) { played.push({ path, start, outputs, guard }); },
  });
  const schedule = (phase, date) => fx.onSunSchedule(JSON.stringify({ phase, boundary: date + ':' + phase }));
  return { fx, played, commands, schedule };
}

test('each boundary is requested once, including the first observation', () => {
  const { fx, played, schedule } = controller();
  fx.Settings.wallDayNight = false;
  schedule('day', '2026-11-28');
  expect(fx.variantProc.running).toBe(false);
  fx.Settings.wallDayNight = true;
  schedule('day', '2026-11-28');
  expect(fx.variantProc.command.slice(-3)).toEqual(['variant', 'day', '--fetch']);
  fx.variantProc.running = false;
  fx.applyVariantResult(JSON.stringify({ path: '/w/sunrise.jpg', outputs: ['DP-3'] }), fx.lastBoundary);
  fx.onDayNightReady();
  expect(played[0].outputs).toEqual(['DP-3']);
  schedule('day', '2026-11-28');
  expect(fx.variantProc.running).toBe(false);
  schedule('night', '2026-11-28');
  expect(fx.variantProc.command.slice(-3)).toEqual(['variant', 'night', '--fetch']);
});

test('busy and blocked states defer the latest boundary and guard the handoff', () => {
  const { fx, commands, played, schedule } = controller();
  fx.phase = 'revealing';
  schedule('night', '2026-11-28');
  expect(fx.variantProc.running).toBe(false);
  fx.sunBlocked = true;
  fx.phase = '';
  schedule('day', '2026-11-29');
  fx.onDayNightReady();
  expect(fx.variantProc.running).toBe(false);
  fx.sunBlocked = false;
  fx.onDayNightReady();
  expect(fx.variantProc.boundary).toBe('2026-11-29:day');
  fx.variantProc.running = false;
  fx.applyVariantResult(JSON.stringify({ path: '/w/sunrise.jpg', outputs: ['DP-3'] }), fx.lastBoundary);
  fx.onDayNightReady();
  expect(played).toHaveLength(1);
  fx.sunBlocked = true;
  expect(played[0].guard()).toBe(false);
  fx.onDayNightReady();
  expect(played).toHaveLength(1);
  fx.sunBlocked = false;
  fx.onDayNightReady();
  expect(played).toHaveLength(2);
  expect(played[1].guard()).toBe(true);
  played[1].start();
  expect(commands[0].slice(-2)).toEqual(['apply-variant', '/w/sunrise.jpg']);
});
