import test from 'node:test';
import assert from 'node:assert/strict';
import { getBookingConversations, getBookingMessages, sendBookingMessage } from '../src/services/bookingService.js';

test('booking messages use the existing authenticated routes and send only trimmed text', async (t) => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({ url, ...options });
    return new Response(JSON.stringify(options.method === 'POST' ? { id: 1, message: 'Hello' } : []), { status: options.method === 'POST' ? 201 : 200 });
  });
  await getBookingConversations('studio-token');
  await getBookingMessages('studio-token', 12);
  const result = await sendBookingMessage('studio-token', 12, '  Hello  ');
  assert.equal(calls[0].url, '/api/bookings/conversations');
  assert.equal(calls[1].url, '/api/bookings/12/messages');
  assert.equal(calls[2].headers.Authorization, 'Bearer studio-token');
  assert.deepEqual(JSON.parse(calls[2].body), { message: 'Hello' });
  assert.equal(result.id, 1);
});

test('invalid messages never reach the server; boundary length is accepted', async (t) => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => { calls++; return new Response('{}', { status: 201 }); });
  for (const value of [null, '', ' \n ', 'x'.repeat(1001)]) {
    await assert.rejects(sendBookingMessage('token', 1, value), /between 1 and 1000/);
  }
  assert.equal(calls, 0);
  await sendBookingMessage('token', 1, 'x'.repeat(1000));
  assert.equal(calls, 1);
});

test('safe API failures propagate without retrying a send', async (t) => {
  let calls = 0;
  const mock = t.mock.method(globalThis, 'fetch', async () => { calls++; return new Response('{}', { status: 404 }); });
  await assert.rejects(getBookingMessages('token', 99), /Booking not found/);
  mock.mock.mockImplementation(async () => { calls++; return new Response('{}', { status: 401 }); });
  await assert.rejects(getBookingConversations('expired'), /session has expired/);
  mock.mock.mockImplementation(async () => { calls++; throw new Error('network'); });
  await assert.rejects(sendBookingMessage('token', 1, 'hello'), /Unable to connect/);
  assert.equal(calls, 3);
});
