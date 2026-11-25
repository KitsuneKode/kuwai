import { test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { notesFor, due } from '../../shell/services/welcomeNotes.mjs';

test('a release section becomes plain bullets with their group', () => {
  const md = '# Changelog\n\n## Unreleased\n- not this\n\n## 0.2.0 — 2026-12-01\n\n### The notch\n- One `surface`, the\n  [notch](x) grown\n- Two\n\n### Install\n- **Three**\n\n## 0.1.0\n- old\n';
  expect(notesFor(md, '0.2.0')).toEqual([
    { group: 'The notch', text: 'One surface, the notch grown' },
    { group: 'The notch', text: 'Two' },
    { group: 'Install', text: 'Three' },
  ]);
  expect(notesFor(md, '0.3.0')).toEqual([]);
});
test('which welcome is due', () => {
  expect(due('', '0.2.0')).toBe('first');
  expect(due('0.1.0', '0.2.0')).toBe('new');
  expect(due('0.2.0', '0.2.0')).toBe('');
  expect(due('0.10.0', '0.9.1')).toBe('');
  expect(due('0.1.0', '')).toBe('');
});
test('the shipped changelog has notes for the shipped version', () => {
  const v = readFileSync(new URL('../../VERSION', import.meta.url), 'utf8').trim();
  const md = readFileSync(new URL('../../CHANGELOG.md', import.meta.url), 'utf8');
  expect(notesFor(md, v).length).toBeGreaterThan(2);
});
