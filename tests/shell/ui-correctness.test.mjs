import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';
test('proximity follows visible monitor center rather than capped host center',()=>{
 const s=functions('shell/modules/island/IslandBar.qml',['inZone'],{onThisScreen:true,localX:960,localY:25,width:1120,screen:{width:1920},restW:260,restH:30,top:0});
 expect(s.inZone(0)).toBe(true);s.localX=560;expect(s.inZone(0)).toBe(false);
});
test('failed package review can be retried without losing other package reviews',()=>{
 let requests=0;
 const s=functions('shell/services/Updates.qml',['review'],{reviews:{a:{error:'offline'},b:{head:'good'}},reviewing:'',reviewQueue:[],nextReview(){requests++;}});
 s.review('a');expect(requests).toBe(1);expect(s.reviews.b.head).toBe('good');
});
test('default accent chooses readable dark ink for small text',()=>{
 const src=readFileSync(new URL('../../shell/config/Theme.qml',import.meta.url),'utf8');
 const expression=src.match(/readonly property color onAccent: (.+)/)[1];
 const scope={accent:{r:10/255,g:132/255,b:1}};
 if(src.includes('function contrastInk(')) functions('shell/config/Theme.qml',['contrastInk','luminance'],scope);
 expect(new Function('s','with(s){return '+expression+'}')(scope)).toBe('#000000');
});

test('overview includes XWayland windows even when capture is unavailable',()=>{
 const t={workspace:{id:2},wayland:null,address:'abc'};
 const s=functions('shell/modules/overview/Overview.qml',['windowsOf'],{Hyprland:{toplevels:{values:[t]}}});
 expect(s.windowsOf(2)).toEqual([t]);
});

test('display preset request does not publish success before state-file acknowledgement',()=>{
 let command;
 const s=functions('shell/services/Display.qml',['setPreset'],{presets:[{id:'movie'}],choice:'everyday',auto:'',autoWhy:'',requestedPreset:'',presetError:'',run(c,done){command=c;},presetApply:{running:false},presetDeadline:{restart(){},stop(){}},presetGeneration:0});
 s.setPreset('movie');expect(s.choice).toBe('everyday');expect(s.requestedPreset).toBe('movie');
});

test('approval is not displayed before helper persistence succeeds',()=>{
 const s=functions('shell/services/Updates.qml',['approve'],{reviews:{a:{head:'sha'}},bin:'fixture',approvedSha:{},setExcluded(){},Quickshell:{execDetached(){}},enqueueMutation(){}});
 s.approve('a');expect(s.approvedSha.a).toBeUndefined();
});

test('late review from an older check cannot replace current review state',()=>{
 const s=functions('shell/services/Updates.qml',['acceptReview'],{reviewEpoch:2,reviews:{a:{head:'new'}},reviewing:'a'});
 s.acceptReview('{"head":"old"}',1);expect(s.reviews.a.head).toBe('new');
});
test('failed approval persistence keeps package unapproved and explains failure',()=>{
 const s=functions('shell/services/Updates.qml',['finishMutation'],{mutationCurrent:{op:'approve',name:'a',sha:'sha'},reviews:{a:{head:'sha'}},approvedSha:{},mutationError:''});
 s.finishMutation(1);expect(s.approvedSha.a).toBeUndefined();expect(s.mutationError.length).toBeGreaterThan(0);
});

test('new display request cancels prior readback deadline and bounds command lifetime',()=>{
 let stopped=0;
 const s=functions('shell/services/Display.qml',['setPreset'],{presets:[{id:'movie'}],requestedPreset:'',presetError:'',presetApply:{running:false},presetDeadline:{stop(){stopped++;}}});
 s.setPreset('movie');expect(stopped).toBe(1);expect(s.presetApply.command[0]).toBe('timeout');
});

test('completed power hold resets progress so the next use requires a full hold',()=>{
 let fired=0;
 const src=readFileSync(new URL('../../shell/modules/lock/HoldButton.qml',import.meta.url),'utf8');
 const s={holding:true,held:1,fired(){fired++;}};s.btn=s;
 if(src.includes('function fireHeld(')) functions('shell/modules/lock/HoldButton.qml',['fireHeld'],s);
 const finish=new Function('btn',src.match(/onFinished: (.+)/)[1]);
 finish(s);expect(fired).toBe(1);expect(s.held).toBe(0);
 s.holding=false;finish(s);expect(fired).toBe(1);
});

test('the standalone auth prompt uses the same readable accent contract',()=>{
 const src=readFileSync(new URL('../../shell-auth/config/Theme.qml',import.meta.url),'utf8');
 const expression=src.match(/readonly property color onAccent: (.+)/)[1];
 const scope={accent:{r:10/255,g:132/255,b:1}};
 if(src.includes('function contrastInk('))functions('shell-auth/config/Theme.qml',['contrastInk','luminance'],scope);
 expect(new Function('s','with(s){return '+expression+'}')(scope)).toBe('#000000');
});
