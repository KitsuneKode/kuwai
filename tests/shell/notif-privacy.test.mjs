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

import { eventTitle } from '../../shell/services/notifPrivacy.mjs';
import { functions } from '../helpers/qml.mjs';
import * as MeetingLogic from '../../shell/services/meeting.mjs';

describe('the next event on the lock screen and the saver', () => {
  const standup = { title: 'Standup', start: 0, private: false };
  const lock = (o) => ctx(Object.assign({ place: 'lock' }, o));
  test('its title only where the lock shows messages in full ("never")', () => {
    expect(eventTitle(standup, lock({ mode: 'never' }))).toBe('Standup');
    expect(eventTitle(standup, lock({ mode: 'lock' }))).toBe('');
    expect(eventTitle(standup, lock({ mode: 'always' }))).toBe('');
    expect(eventTitle(standup, ctx({ place: 'saver', mode: 'never' }))).toBe('Standup');
    expect(eventTitle(standup, ctx({ place: 'saver', mode: 'lock' }))).toBe('');
  });
  test('a private or confidential event: never its title, whatever the setting', () => {
    expect(eventTitle(Object.assign({}, standup, { private: true }), lock({ mode: 'never' }))).toBe('');
  });
  test('while sharing the screen: no title anywhere', () => {
    expect(eventTitle(standup, lock({ mode: 'never', sharing: true }))).toBe('');
    expect(eventTitle(standup, ctx({ sharing: true }))).toBe('');
  });
  test('sensitive words or a person kept private in the title hide it', () => {
    expect(eventTitle({ title: 'Reset bank password' }, lock({ mode: 'never' }))).toBe('');
    expect(eventTitle({ title: 'Lunch with Anna' }, lock({ mode: 'never', privateSenders: 'anna' }))).toBe('');
  });
  test('no title or the calendar\'s stand-in: none to show', () => {
    expect(eventTitle({ title: '(No title)' }, lock({ mode: 'never' }))).toBe('');
    expect(eventTitle({ title: '  ' }, lock({ mode: 'never' }))).toBe('');
    expect(eventTitle(null, lock({ mode: 'never' }))).toBe('');
  });
  test('the desktop shows it unless everything is private', () => {
    expect(eventTitle(standup, ctx())).toBe('Standup');
    expect(eventTitle(standup, ctx({ mode: 'always' }))).toBe('');
  });
});

describe('which event the lock names', () => {
  const ics = (extra) => ['BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'DTSTART:20261127T140000', 'DTEND:20261127T150000', 'SUMMARY:Review'].concat(extra, ['END:VEVENT', 'END:VCALENDAR']).join('\n');
  const cal = () => functions('shell/services/Calendar.qml', ['parse', 'parseTime', 'icsText', 'nextToday'], { events: [], MeetingLogic });
  test('CLASS:PRIVATE and CONFIDENTIAL are private; PUBLIC and none are not', () => {
    const c = cal();
    const at = Date.now;
    Date.now = () => new Date(2026, 10, 27, 9).getTime();
    try {
      expect(c.parse(ics(['CLASS:PRIVATE']))[0].private).toBe(true);
      expect(c.parse(ics(['CLASS:CONFIDENTIAL']))[0].private).toBe(true);
      expect(c.parse(ics(['CLASS:PUBLIC']))[0].private).toBe(false);
      expect(c.parse(ics([]))[0].private).toBe(false);
    } finally { Date.now = at; }
  });
  test('the next one today within the window; not tomorrow, not all-day, not one already started', () => {
    const c = cal();
    const now = new Date(2026, 10, 27, 22, 0).getTime(), h = 3600000;
    c.events = [
      { start: now - h, end: now + h, allDay: false, title: 'Started' },
      { start: now, end: now + h, allDay: true, title: 'All day' },
      { start: now + 2.5 * h, end: now + 3 * h, allDay: false, title: 'Tomorrow' }
    ];
    expect(c.nextToday(now, 4 * h)).toBe(null);
    c.events.push({ start: now + 0.5 * h, end: now + h, allDay: false, title: 'Late call' });
    c.events.sort((a, b) => a.start - b.start);
    expect(c.nextToday(now, 4 * h).title).toBe('Late call');
    expect(c.nextToday(now, 0.25 * h)).toBe(null);
  });
});
