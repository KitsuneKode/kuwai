import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const bar = readFileSync(new URL('../../shell/modules/island/IslandBar.qml', import.meta.url), 'utf8');

test("a panel's title and status stop before the centred section tabs, cut with … instead of running under them", () => {
  expect(bar).toMatch(/id: secRow\n\s*visible: win\.sectioned\n\s*anchors\.horizontalCenter: parent\.horizontalCenter/);
  expect(bar).toMatch(/id: headRow\n\s*readonly property real room: Math\.max\(0, \(secRow\.visible \? secRow\.x - Theme\.s3/);
  const head = bar.slice(bar.indexOf('id: headRow'), bar.indexOf('id: headRow') + 1800);
  expect(head).toMatch(/id: headTitle[\s\S]*?width: Math\.min\(implicitWidth, headRow\.room\)[\s\S]*?elide: Text\.ElideRight/);
  expect(head).toMatch(/readonly property real room: headRow\.room - headTitle\.width - headRow\.spacing[\s\S]*?width: Math\.min\(implicitWidth, room\)[\s\S]*?elide: Text\.ElideRight/);
});
