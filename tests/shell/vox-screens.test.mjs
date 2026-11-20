import { describe, expect, test } from 'bun:test';
import { plan } from '../../shell/modules/voxtype/voxScreens.mjs';

const edp = { name: 'eDP-1' }, dp = { name: 'DP-3' };

describe('voxtype HUDs across output changes', () => {
  test('the same outputs: nothing is touched', () => {
    expect(plan({ 'eDP-1': edp, 'DP-3': dp }, [edp, dp])).toEqual({ drop: [], add: [], keep: ['eDP-1', 'DP-3'] });
  });
  test('a screen back from power-off (a new output, same name): only its HUD is made again', () => {
    const dpBack = { name: 'DP-3' };
    expect(plan({ 'eDP-1': edp, 'DP-3': dp }, [edp, dpBack])).toEqual({ drop: ['DP-3'], add: ['DP-3'], keep: ['eDP-1'] });
  });
  test('a screen unplugged: its HUD goes, the others stay', () => {
    expect(plan({ 'eDP-1': edp, 'DP-3': dp }, [edp])).toEqual({ drop: ['DP-3'], add: [], keep: ['eDP-1'] });
  });
  test('a screen plugged in: one HUD more', () => {
    expect(plan({ 'eDP-1': edp }, [edp, dp])).toEqual({ drop: [], add: ['DP-3'], keep: ['eDP-1'] });
  });
  test('nothing yet, or no screens', () => {
    expect(plan({}, [edp])).toEqual({ drop: [], add: ['eDP-1'], keep: [] });
    expect(plan(null, null)).toEqual({ drop: [], add: [], keep: [] });
  });
});
