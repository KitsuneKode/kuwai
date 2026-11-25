import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
for (const kind of ['wifi','bluetooth']) {
 const path=kind==='wifi'?'shell/modules/notifications/WifiList.qml':'shell/modules/notifications/BluetoothDevices.qml';
 test(kind+' forget requires confirmation and ignores replaced/disappeared target',()=>{
  let forgotten=0,opened=0;
  const target={known:true,paired:true,name:'Fixture',forget(){forgotten++;}};
  const s=functions(path,['requestForget','confirmForget'],{forgetTarget:null,networks:[target],all:[target],forgetDialog:{open(){opened++;}}});
  s.requestForget(target);expect(opened).toBe(1);expect(forgotten).toBe(0);
  s.networks=[];s.all=[];s.confirmForget();expect(forgotten).toBe(0);
  s.networks=[target];s.all=[target];s.requestForget(target);s.confirmForget();s.confirmForget();
  expect(forgotten).toBe(1);
 });
}
