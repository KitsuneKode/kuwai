import { describe, expect, test } from 'bun:test';
import { hidden, toggleSender, fromPrivateSender } from '../../shell/services/notifPrivacy.mjs';

const chat = { app: 'ZapZap', title: 'Anna', body: 'lunch at 12?' };
const ctx = (o) => Object.assign({ sharing: false, place: 'desktop', mode: 'lock', privateSenders: '' }, o);

describe('where a chat message shows', () => {
  test('on the desktop: shown (the default, "hidden on the lock screen")', () => expect(hidden(chat, ctx())).toBe(false));
  test('on the lock screen: who, not what', () => expect(hidden(chat, ctx({ place: 'lock' }))).toBe(true));
  test('"always hidden" hides it on the desktop too; "always shown" shows it on the lock screen', () => {
    expect(hidden(chat, ctx({ mode: 'always' }))).toBe(true);
    expect(hidden(chat, ctx({ place: 'lock', mode: 'never' }))).toBe(false);
  });
  test('while sharing the screen: nothing, from anyone, even critical', () => {
    expect(hidden(chat, ctx({ sharing: true }))).toBe(true);
    expect(hidden({ app: 'Bank', severity: 'critical', body: 'x' }, ctx({ sharing: true }))).toBe(true);
  });
  test('not a chat app: shown on the lock screen as before', () => expect(hidden({ app: 'Calendar', title: 'Standup', body: 'Room 2' }, ctx({ place: 'lock' }))).toBe(false));
});

describe('what is sensitive whoever sends it', () => {
  test('a password, a PIN, a card or account number: hidden until opened', () => {
    for (const body of ['your new password is hunter2', 'UPI PIN changed', 'Card ending 4421 charged', 'Account number 12345']) expect(hidden({ app: 'ZapZap', title: 'Bank', body }, ctx())).toBe(true);
  });
  test('ordinary words that look alike stay: pinned, account settings', () => {
    expect(hidden({ app: 'ZapZap', title: 'Anna', body: 'pinned the message' }, ctx())).toBe(false);
    expect(hidden({ app: 'Mail', title: 'Your account settings', body: 'updated' }, ctx())).toBe(false);
  });
});

describe('people you keep private', () => {
  test('a name on the list: hidden everywhere until opened', () => {
    expect(fromPrivateSender(chat, 'Mom, anna')).toBe(true);
    expect(hidden(chat, ctx({ privateSenders: 'Mom, anna' }))).toBe(true);
    expect(hidden({ app: 'ZapZap', title: 'Ravi', body: 'hi' }, ctx({ privateSenders: 'Mom, anna' }))).toBe(false);
  });
  test('the menu adds and removes a name, whatever its case', () => {
    expect(toggleSender('', 'Anna')).toBe('Anna');
    expect(toggleSender('Mom, Anna', 'anna')).toBe('Mom');
    expect(toggleSender('Mom', 'Ravi')).toBe('Mom, Ravi');
  });
});

describe('mail and texts are messages too', () => {
  test('on the lock screen: who, not what', () => {
    for (const app of ['Gmail', 'Thunderbird', 'Evolution', 'KDE Connect', 'Messages']) expect(hidden({ app, title: 'Anna', body: 'the contract' }, ctx({ place: 'lock' }))).toBe(true);
  });
  test('on the desktop by default: shown', () => expect(hidden({ app: 'Gmail', title: 'Anna', body: 'x' }, ctx())).toBe(false));
});
