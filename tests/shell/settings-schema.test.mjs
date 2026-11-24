import { test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';
const lib=readFileSync(new URL('../../shell/config/settingsSchema.js',import.meta.url),'utf8').replace(/^\.pragma library\s*$/m,'');
const Contract=new Function(lib+'\nreturn {entry,valid,defaults,parse,overrides,rows};')();
const schema=JSON.parse(readFileSync(new URL('../../shell/config/settings-schema.json',import.meta.url),'utf8'));
function oldSettings() {
  const s={clock24:true,idleOwner:'shell'};
  return functions('shell/config/Settings.qml',['set'],{s, schema, Contract, queue:[], writeError:'', drain(){}, writer:{running:false}});
}
test('GUI rejects wrong types, unknown keys and invalid enum before changing state',()=>{
  const root=oldSettings();
  for (const [key,value] of [['clock24',0],['idleOwner','typo'],['surprise',true]]) expect(root.set(key,value)).toBe(false);
  expect(root.s.clock24).toBe(true);
  expect(root.s.idleOwner).toBe('shell');
});

test('every typed caller property has a schema entry and a valid default',()=>{
  const src=readFileSync(new URL('../../shell/config/Settings.qml',import.meta.url),'utf8');
  const keys=[...src.matchAll(/readonly property (?:bool|int|real|string|var) (\w+): value\(/g)].map(m=>m[1]);
  expect(keys.sort()).toEqual(schema.settings.map(e=>e.key).sort());
  for (const e of schema.settings) { expect(Contract.valid(e,e.default)).toBe(true); expect(e.restartScope).toBeTruthy(); expect(e.section).toBeTruthy(); }
});
test('last good document survives a malformed reload and false/zero are overrides',()=>{
  const r=functions('shell/config/Settings.qml',['accept'],{schema,Contract,document:{clock24:false,hoverDelay:0},loaded:true,loadError:''});
  expect(r.accept('{bad')).toBe(false); expect(r.document).toEqual({clock24:false,hoverDelay:0});
  expect(r.accept('{"clock24":0}')).toBe(false); expect(r.document.clock24).toBe(false);
  expect(r.accept('{"clock24":true}')).toBe(true); expect(r.loadError).toBe('');
  const result=Contract.overrides({clock24:false,hoverDelay:0,future:[]},{key:'clock24',reset:true},[{key:'showSeconds',value:true}]);
  expect(Object.hasOwn(result,'clock24')).toBe(false); expect(result.hoverDelay).toBe(0); expect(result.showSeconds).toBe(true);
});
test('known fields validate and unknown fields survive without prototype changes',()=>{
  const doc=Contract.parse(schema,'{"future":[null,[]],"__proto__":{"clock24":false}}');
  const values=Contract.overrides(doc,null,[]);
  expect(values.future).toEqual([null,[]]); expect(Object.getPrototypeOf(values)).toBe(null);
  expect(()=>Contract.parse(schema,'{"_schemaVersion":99}')).toThrow();
});
test('search metadata has stable identity and supports non-Latin text',()=>{
  const data={...schema, additionalRows:[{page:'bar',label:'天気',detail:'場所',group:'',words:'天気 場所'}]};
  const rows=Contract.rows(data); expect(rows.some(r=>r.label==='天気')).toBe(true);
  expect(new Set(rows.map(r=>JSON.stringify([r.page,r.label,r.group]))).size).toBe(rows.length);
});
test('typed reads use schema defaults before dependent bindings settle',()=>{
  const r=functions('shell/config/Settings.qml',['value','isDefault'],{values:undefined,overrides:undefined,schema,Contract});
  expect(r.value('clock24')).toBe(true); expect(r.value('idleLockAc')).toBe(300);
  expect(r.isDefault('clock24')).toBe(true);
});
test('a pre-write file read cannot replace a newer acknowledged value',async ()=>{
  const SettingsState=await import('../../shell/config/settingsState.mjs');
  const r=functions('shell/config/Settings.qml',['dispatch','loadedFile'],{
    SettingsState,
    _sm:{readBusy:true,readGeneration:2,generation:3,activeWrite:null,queue:[],loaded:true,needsRead:false},
    writer:{running:false},document:{idleOwner:'hypridle'},readLater:{restart(){}},drain(){},
    accept(text){ this.document=JSON.parse(text); }
  });
  r.loadedFile('{"idleOwner":"shell"}');
  expect(r.document.idleOwner).toBe('hypridle'); expect(r._sm.needsRead).toBe(true);
  r._sm=Object.assign({},r._sm,{readBusy:true,readGeneration:3,needsRead:false});
  r.loadedFile('{"idleOwner":"shell"}');
  expect(r.document.idleOwner).toBe('shell');
});
test('bedtime choices find the Power wellbeing row without Screensaver contamination',()=>{
  const searchLib=readFileSync(new URL('../../shell/services/settingsSearch.js',import.meta.url),'utf8').replace(/^\.pragma library\s*$/m,'');
  const {search}=new Function(searchLib+'\nreturn {search};')();
  const sections=[{id:'power',label:'Power & Idle',keys:'wellbeing sleep bedtime'},{id:'saver',label:'Screensaver',keys:'screensaver'}];
  const results=search(sections,Contract.rows(schema),'00:30');
  expect(results.length).toBeGreaterThan(0);
  expect(results.every(r=>r.section.id==='power' && r.row.label==='After' && r.row.group==='Wellbeing')).toBe(true);
});
