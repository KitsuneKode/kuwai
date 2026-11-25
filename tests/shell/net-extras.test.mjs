import { test, expect } from 'bun:test';
import { vpns, printers, jobs, iwdStation, nmFields } from '../../shell/services/netExtras.mjs';

test('VPN and WireGuard connections, with escaped colons', () => {
  const out = vpns('Home Wi\\:Fi:aaa:802-11-wireless:yes\nWork:bbb:vpn:no\nwg0:ccc:wireguard:yes\n');
  expect(out).toEqual([{ name: 'Work', uuid: 'bbb', kind: 'VPN', active: false }, { name: 'wg0', uuid: 'ccc', kind: 'WireGuard', active: true }]);
  expect(nmFields('a\\:b:c')).toEqual(['a:b', 'c']);
});
test('printers, the default, and queued jobs', () => {
  const p = printers('printer Office is idle.  enabled since x\nprinter Label disabled since y -\nsystem default destination: Office\n');
  expect(p).toEqual([{ name: 'Office', state: 'idle', default: true }, { name: 'Label', state: 'disabled', default: false }]);
  expect(jobs('Office-12   ada   20480   Wed 26 Nov\n')).toEqual([{ id: 'Office-12', printer: 'Office', user: 'ada', bytes: 20480 }]);
});
test('iwd station', () => {
  expect(iwdStation('  State      connected\n  Connected network     Home 5G   \n')).toEqual({ network: 'Home 5G', state: 'connected' });
});
