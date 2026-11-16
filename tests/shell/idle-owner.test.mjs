import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';
const src=readFileSync(new URL('../../shell/services/Idle.qml',import.meta.url),'utf8');
test('requesting hypridle keeps shell protection until destination readiness is confirmed',()=>{
  const expression=src.match(/readonly property bool enabled: (.+)/)[1];
  const root={confirmedOwner:'shell'};
  expect(new Function('root','Settings','return '+expression)(root,{idleOwner:'hypridle'})).toBe(true);
});
function owner() {
 const s=functions('shell/services/Idle.qml',['reconcileOwner','ownerStarted','ownerChecked'],{
  Settings:{idleOwner:'hypridle'},confirmedOwner:'shell',ownerError:'',attemptOwner:'',
  ownerCommand:{running:false},ownerCheck:{running:false},
 });
 return s;
}
test('failed destination start retains shell policy and exposes recovery error',()=>{
 const s=owner();s.reconcileOwner();s.ownerCommand.running=false;s.ownerStarted(1);
 expect(s.confirmedOwner).toBe('shell');expect(s.ownerError.length).toBeGreaterThan(0);
});
test('shell relinquishes only after successful start and is-active acknowledgement',()=>{
 const s=owner();s.reconcileOwner();s.ownerCommand.running=false;s.ownerStarted(0);
 expect(s.confirmedOwner).toBe('shell');expect(s.ownerCheck.running).toBe(true);
 s.ownerCheck.running=false;s.ownerChecked(0);expect(s.confirmedOwner).toBe('hypridle');
});
test('rapid reversal ignores old acknowledgement and keeps shell enabled',()=>{
 const s=owner();s.reconcileOwner();s.Settings.idleOwner='shell';s.reconcileOwner();
 s.ownerCommand.running=false;s.ownerStarted(0);
 expect(s.confirmedOwner).toBe('shell');expect(s.ownerCommand.running).toBe(true);
 expect(s.attemptOwner).toBe('shell');
});
test('a dead hypridle restores shell policy before retry',()=>{
 const s=owner();s.confirmedOwner='hypridle';s.attemptOwner='hypridle';s.ownerChecked(3);
 expect(s.confirmedOwner).toBe('shell');expect(s.ownerError.length).toBeGreaterThan(0);
});
