import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
test('launch failure restores greeter presentation and permits another login', () => {
  let stopped=0, retried=0;
  const s=functions('shell/greeter.qml',['fail','submit'], {
    locked:false, leaving:true, checking:true,password:'synthetic',error:'',failures:0,
    handoff:{stop(){stopped++;}},user:'fixture',GreetdState:{Inactive:0},
    trace(){},Greetd:{available:true,state:0,cancelSession(){},createSession(){retried++;}},
  });
  s.fail('Synthetic launch failure');
  expect(s.locked).toBe(true); expect(s.leaving).toBe(false);
  expect(s.password).toBe(''); expect(s.error).toBe('Synthetic launch failure');
  expect(stopped).toBe(1);
  s.password='second synthetic'; s.submit(); expect(retried).toBe(1);
});
