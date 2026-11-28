import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
import * as Sizes from '../../shell/services/sizes.mjs';

// services/Alerts.qml's commit(): what earns the island's orange pill.
function alerts(v) {
  const s = functions('shell/services/Alerts.qml', ['commit'], {
    active: [], shown: {}, hot: 0, batteryLow: false, banner: null,
    bannerFor: { restart() {} }, Screens: { focusedName: '' }, Sizes,
  });
  s.commit(v);
  return s.active.map(a => a.id);
}
const GB = 1048576;     // /proc/meminfo counts kB

test('a full swap beside plenty of free memory is not a warning', () => {
  expect(alerts({ MemTotal: 23 * GB, MemAvailable: 13 * GB, SwapTotal: 18 * GB, SwapFree: 1.6 * GB })).not.toContain('swap');
});

test('a full swap while memory is short is', () => {
  expect(alerts({ MemTotal: 23 * GB, MemAvailable: 3 * GB, SwapTotal: 18 * GB, SwapFree: 1 * GB })).toContain('swap');
});
