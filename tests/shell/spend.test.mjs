// Spend from local agent logs (lib/spend.mjs, bin/kuwai-spend).
import { describe, expect, test } from 'bun:test';
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { claudeLine, codexLine, opencodeMessage, priceOf, costOf, add, summary, dayOf, tokensText, completeLines } from '../../lib/spend.mjs';

const prices = JSON.parse(readFileSync(new URL('../../lib/spend-prices.json', import.meta.url), 'utf8'));
const at = '2026-11-20T10:00:00.000Z';
const claude = (id, model, u) => ({ type: 'assistant', timestamp: at, message: { id, model, usage: u } });

describe('reading the logs', () => {
  test('a Claude Code message: its tokens, 1-hour cache writes apart', () => {
    const r = claudeLine(claude('m1', 'claude-opus-5-5', { input_tokens: 2, output_tokens: 251, cache_creation_input_tokens: 29457, cache_read_input_tokens: 24569, cache_creation: { ephemeral_1h_input_tokens: 29457, ephemeral_5m_input_tokens: 0 } }));
    expect(r).toMatchObject({ provider: 'claude', id: 'm1', in: 2, out: 251, cacheWrite: 0, cacheWrite1h: 29457, cacheRead: 24569, day: dayOf(Date.parse(at)) });
    expect(claudeLine({ type: 'user', message: { content: 'hi' } })).toBeNull();
  });
  test('Codex: the model from turn_context, cached input taken out of input', () => {
    const ctx = {};
    expect(codexLine({ type: 'turn_context', payload: { model: 'gpt-5.5-codex' } }, ctx)).toBeNull();
    const r = codexLine({ type: 'event_msg', timestamp: at, payload: { type: 'token_count', info: { last_token_usage: { input_tokens: 29726, cached_input_tokens: 6912, output_tokens: 217 } } } }, ctx);
    expect(r).toMatchObject({ provider: 'codex', model: 'gpt-5.5-codex', in: 22814, cacheRead: 6912, out: 217 });
  });
  test('opencode: its own cost when it has one; reasoning counts as output', () => {
    const r = opencodeMessage({ role: 'assistant', modelID: 'claude-opus-4.5', time: { created: Date.parse(at) }, cost: 0.42, tokens: { input: 10, output: 5, reasoning: 3, cache: { read: 100, write: 7 } } });
    expect(r).toMatchObject({ provider: 'opencode', in: 10, out: 8, cacheRead: 100, cacheWrite: 7, cost: 0.42 });
    expect(costOf(prices, r)).toBe(0.42);
  });
});

describe('pricing', () => {
  test('current models from the table, cache reads and writes as it says', () => {
    expect(priceOf(prices, 'claude-opus-5-5')).toMatchObject({ in: 4, out: 20, cacheRead: 0.2 });
    expect(priceOf(prices, 'claude-sonnet-5')).toMatchObject({ in: 2 });
    expect(priceOf(prices, 'claude-sonnet-5-5')).toMatchObject({ cacheRead: 0.1 });
    // 1M in, 1M out, 1M 5-minute writes (1.25×), 1M 1-hour writes (2×), 1M reads.
    const c = costOf(prices, { provider: 'claude', model: 'claude-opus-5-5', in: 1e6, out: 1e6, cacheWrite: 1e6, cacheWrite1h: 1e6, cacheRead: 1e6 });
    expect(c).toBeCloseTo(4 + 20 + 5 + 8 + 0.2, 6);
  });
  test('a model the table doesn\'t know: tokens without a price', () => {
    expect(costOf(prices, { provider: 'codex', model: 'gpt-5.5-codex', in: 1, out: 1, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0 })).toBeNull();
    const days = {};
    add(days, { provider: 'codex', model: 'x', day: '2026-11-20', in: 10, out: 0, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0 }, null);
    expect(summary(days, '2026-11-20').codex.today).toEqual({ tokens: 10, cost: 0, priced: false });
  });
  test('today and the last seven days', () => {
    const days = {};
    const rec = (day, n) => ({ provider: 'claude', model: 'claude-haiku-5-5', day, in: n, out: 0, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0 });
    add(days, rec('2026-11-20', 1e6), 0.1);
    add(days, rec('2026-11-14', 1e6), 0.1);
    add(days, rec('2026-11-13', 1e6), 0.1);           // eight days back: not in the week
    const s = summary(days, '2026-11-20');
    expect(s.claude.today.tokens).toBe(1e6);
    expect(s.claude.week).toEqual({ tokens: 2e6, cost: 0.2, priced: true });
    expect(tokensText(1234567)).toBe('1.2M');
    expect(tokensText(845000)).toBe('845K');
  });
  test('only complete lines, offsets in bytes', () => {
    const { lines, used } = completeLines(Buffer.from('é1\né2\npart'));
    expect(lines).toEqual(['é1', 'é2']);
    expect(used).toBe(Buffer.byteLength('é1\né2\n'));
  });
});

describe('kuwai-spend reads only what is new', () => {
  const bin = new URL('../../bin/kuwai-spend', import.meta.url).pathname;
  test('appended lines are counted once, a repeated message id once, a half-written line waits', () => {
    const home = mkdtempSync(join(tmpdir(), 'kuwai-spend-'));
    const dir = join(home, '.claude/projects/p');
    mkdirSync(dir, { recursive: true });
    const log = join(dir, 's.jsonl');
    const now = new Date().toISOString();
    const line = (id, n) => JSON.stringify({ type: 'assistant', timestamp: now, message: { id, model: 'claude-haiku-5-5', usage: { input_tokens: n, output_tokens: 0 } } }) + '\n';
    const run = () => {
      const r = spawnSync('node', [bin], { env: { HOME: home, XDG_CACHE_HOME: join(home, 'cache'), PATH: process.env.PATH }, encoding: 'utf8' });
      return JSON.parse(r.stdout.trim().split('\n').pop()).providers.claude.today.tokens;
    };
    writeFileSync(log, line('a', 100) + line('a', 100) + line('b', 10));   // a's second block repeats its usage
    expect(run()).toBe(110);
    appendFileSync(log, line('c', 1));
    expect(run()).toBe(111);
    expect(run()).toBe(111);                                               // nothing new: nothing added
    appendFileSync(log, '{"type":"assistant","timestamp":"' + now);        // half a line: waits
    expect(run()).toBe(111);
  });
});
