import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
const Qt={Key_Escape:1,Key_Left:2,Key_Right:3,Key_Up:4,Key_Down:5,Key_PageUp:6,Key_PageDown:7,Key_Home:8,Key_End:9,Key_Return:10,Key_Enter:11,Key_Space:12,ShiftModifier:1};
test('calendar Enter selects the focused day and unrelated keys are not consumed',()=>{
 let chosen;
 const s=functions('shell/modules/clipboard/DatePicker.qml',['key','shift'],{Qt,Dates:{lead:d=>(d.getDay()+6)%7},open:true,focusedDay:new Date(2026,10,15),month:new Date(2026,10,1),pickDay(d,extend){chosen=[d.getDate(),!!extend];}});
 expect(s.key({key:Qt.Key_Return,modifiers:Qt.ShiftModifier})).toBe(true);
 expect(chosen).toEqual([15,true]);expect(s.key({key:99,modifiers:0})).toBe(false);
});
test('calendar arrows move by days, including month boundaries',()=>{
 const s=functions('shell/modules/clipboard/DatePicker.qml',['key','shift'],{Qt,Dates:{lead:d=>(d.getDay()+6)%7},open:true,focusedDay:new Date(2026,10,1),month:new Date(2026,10,1)});
 s.key({key:Qt.Key_Left,modifiers:0});expect([s.focusedDay.getMonth(),s.focusedDay.getDate()]).toEqual([9,31]);
});
test('local-day selection ends at next midnight across daylight saving',()=>{
 const old=process.env.TZ;process.env.TZ='America/New_York';
 try {
  let bounds;
  const s=functions('shell/modules/clipboard/DatePicker.qml',['pickDay','startOf'],{focusedDay:null,day:86400000,anchorDay:0,fmt(){return 'day';},picked(a,b){bounds=[a,b];}});
  s.pickDay(new Date(2026,2,8),false);
  expect(new Date(bounds[1]).getHours()).toBe(0);
  expect(new Date(bounds[1]).getDate()).toBe(9);
  expect(bounds[1]-bounds[0]).toBe(23*3600000);
 }finally {if(old===undefined)delete process.env.TZ;else process.env.TZ=old;}
});

test('pointer date selection also updates the next keyboard navigation origin',()=>{
 const s=functions('shell/modules/clipboard/DatePicker.qml',['pickDay','startOf'],{focusedDay:new Date(2026,0,1),anchorDay:0,fmt(){return 'day';},picked(){}});
 s.pickDay(new Date(2026,0,5),false);expect(s.focusedDay.getDate()).toBe(5);
});
