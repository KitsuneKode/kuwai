import { describe, expect, test } from 'bun:test';
import { styledSafe, plainStyled } from '../../shell/services/notifMarkup.mjs';

const tags = (s) => (s.match(/<[^>]*>?/g) || []).map(t => t.toLowerCase());
const allowed = new Set(['<b>', '</b>', '<i>', '</i>', '<u>', '</u>', '<em>', '</em>', '<strong>', '</strong>', '<br>']);

describe('a notification body for StyledText keeps only bare formatting tags', () => {
    test('bold, italic and line breaks stay', () => {
        expect(styledSafe('<b>Build</b> passed<br/>in <i>3 min</i>')).toBe('<b>Build</b> passed<br>in <i>3 min</i>');
    });
    for (const body of [
        '<img src="https://evil.example/p.png">',
        '<img src="https://evil.example/p.png"',
        'hi <img src=file:///etc/passwd',
        '<IMG SRC="x"/>',
        '<a href="https://evil.example">x</a>',
        '<b onclick="x">bold</b>',
        '<font color=red>x</font>',
        '<<img src=x>img src=y>',
        '<b>ok</b><img src="//evil.example/a"',
    ]) {
        test(`no tag that could load or link survives: ${body}`, () => {
            const out = styledSafe(body);
            for (const t of tags(out)) expect(allowed.has(t)).toBe(true);
            expect(out).not.toMatch(/<img/i);
        });
    }
    test('scripts and styles go with their content', () => {
        expect(styledSafe('a<script>alert(1)</script>b<style>x{}</style>c')).toBe('abc');
    });
    test('text that looks like a comparison is shown, not parsed', () => {
        expect(styledSafe('3 < 5 and 7 > 2')).toBe('3 &lt; 5 and 7 &gt; 2');
    });
});

describe('a plain body for StyledText has no tags at all', () => {
    test('closed tags go, an unclosed one is shown as text', () => {
        const out = plainStyled('<b>x</b> <img src="https://evil.example/p"');
        expect(tags(out)).toEqual([]);
        expect(out).toContain('&lt;img');
    });
});
