import { describe, expect, test } from 'bun:test';
import { safeLink, webLink } from '../../shell/services/links.mjs';
import { safeLink as turnSafeLink } from '../../shell/services/ai/turn.mjs';

describe('links from outside the shell', () => {
  test('only the web and mail open', () => {
    for (const ok of ['https://archlinux.org/news/x/', 'http://x.y', 'HTTPS://X.Y', 'mailto:a@b.c', '  https://aur.archlinux.org/packages/x  ']) expect(safeLink(ok)).toBe(true);
    for (const no of ['file:///etc/passwd', 'smb://host/share', 'javascript:alert(1)', 'vscode://open', 't3code://x', '', null, undefined, '-oProxyCommand=x', 'https']) expect(safeLink(no)).toBe(false);
  });
  test('webLink gives the trimmed link or nothing', () => {
    expect(webLink(' https://a.b/c ')).toBe('https://a.b/c');
    expect(webLink('file:///x')).toBe('');
  });
  test('the assistant uses the same check', () => { expect(turnSafeLink).toBe(safeLink); });
});
