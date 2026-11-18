import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
import { readFileSync } from 'node:fs';

test('minimized windows return to the workspace of the clicked island', () => {
  const calls = [];
  const s = functions('shell/modules/island/IslandSplit.qml', ['bringBack'], {
    bar: { screenWs: { id: 12 } },
    Hyprland: { focusedWorkspace: { id: 2 }, dispatch(value) { calls.push(value); } },
  });
  s.bringBack({address:'abc123'});
  expect(Number(calls[0].match(/workspace\s*=\s*(\d+)/)[1])).toBe(12);
});

test('already prefixed window addresses are not prefixed twice', () => {
  const calls = [];
  const s = functions('shell/modules/island/IslandSplit.qml', ['bringBack'], {
    bar: {screenWs:{id:1}}, Hyprland: {focusedWorkspace:{id:1},dispatch(v){calls.push(v);}},
  });
  s.bringBack({address:'0xabc123'});
  expect(calls.join()).not.toContain('0x0x');
});

test('invalid window addresses never dispatch and invalid workspace data uses a safe fallback', () => {
  const calls = [];
  const s = functions('shell/modules/island/IslandSplit.qml', ['bringBack'], {
    bar:{screenWs:{id:'broken'}}, Hyprland:{focusedWorkspace:{id:7},dispatch(v){calls.push(v);}},
  });
  s.bringBack({address:"x'});error('bad')"});
  expect(calls).toHaveLength(0);
  s.bringBack({address:'abc'});
  expect(calls[0]).toContain('workspace = 7');
});

test('rotated monitor hot bands use logical rotated width', () => {
  const s = functions('shell/services/Pointer.qml', ['inHotBand'], {
    hotBand:140, Hyprland:{monitors:{values:[{lastIpcObject:{x:0,y:0,width:1920,height:1080,scale:1,transform:1}}]}},
  });
  expect(s.inHotBand(1500,20)).toBe(false);
  expect(s.inHotBand(1000,20)).toBe(true);
});

function wantsProximity(values = {}) {
  const source = readFileSync(new URL('../../shell/modules/island/IslandBar.qml', import.meta.url), 'utf8');
  const scope = {showBar:true,screenFullscreen:false,hovered:false,tucked:false,near:false,
    Settings:{islandProximity:true,islandRest:'minimal'},restRow:{compact:true},
    Saver:{showing:false,locked:false,screensOff:false},...values};
  const available = source.match(/readonly property bool proximityAvailable: (.+)/);
  if (available) scope.proximityAvailable = new Function('s','with(s){return '+available[1]+'}')(scope);
  return new Function('s','with(s){return '+source.match(/readonly property bool wantsProximity: (.+)/)[1]+'}')(scope);
}

test('hidden and fullscreen surfaces do not keep proximity sampling alive', () => {
  for (const key of ['showing','locked','screensOff']) {
    expect(wantsProximity({Saver:{showing:false,locked:false,screensOff:false,[key]:true}})).toBe(false);
  }
  expect(wantsProximity({screenFullscreen:true})).toBe(false);
  expect(wantsProximity({showBar:false})).toBe(false);
  expect(wantsProximity()).toBe(true);
});

test('auto proximity keeps tracking the exit after its compact row expands', () => {
  expect(wantsProximity({Settings:{islandProximity:true,islandRest:'auto'},restRow:{compact:false},near:true})).toBe(true);
});

test('pointer subscriptions are idempotent across initialization and rapid visibility changes', () => {
  let held = 0;
  const s = functions('shell/modules/island/IslandBar.qml', ['syncPointerRequest'], {
    pointerReady:false, wantsProximity:true, proximitySubscribed:false,
    Pointer:{want(){held++;},unwant(){held--; if(held<0) throw new Error('unbalanced');}},
  });
  s.syncPointerRequest();
  expect(held).toBe(0);
  s.pointerReady = true;
  for(let i=0;i<100;i++) {
    s.wantsProximity = true;
    s.syncPointerRequest(); s.syncPointerRequest();
    expect(held).toBe(1);
    s.wantsProximity = false;
    s.syncPointerRequest(); s.syncPointerRequest();
    expect(held).toBe(0);
  }
});

function pointerSample(value, now = 1200) {
  const source = readFileSync(new URL('../../shell/services/Pointer.qml', import.meta.url), 'utf8');
  const body = source.match(/onRead: data => \{([\s\S]*?)\n            \}/)[1];
  const root = {x:100,y:20,t:1000,vx:0,vy:0,speed:0,hot:false,inHotBand(){return true;}};
  const sock = {connected:true};
  new Function('root','sock','data','Date',body)(root,sock,'{' + value,{now:()=>now});
  return root;
}

test('malformed pointer coordinates cannot overwrite the last valid sample', () => {
  for (const value of ['"x":"bad","y":12', '"x":null,"y":12', '"x":1e309,"y":12']) {
    expect(pointerSample(value)).toMatchObject({x:100,y:20,t:1000,speed:0});
  }
});

test('clock rollback or duplicate sample times do not manufacture huge velocities', () => {
  expect(pointerSample('"x":200,"y":30', 1000).speed).toBe(0);
  expect(pointerSample('"x":200,"y":30', 900).speed).toBe(0);
});
