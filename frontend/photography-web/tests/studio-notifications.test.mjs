import test from 'node:test';
import assert from 'node:assert/strict';
import { getStudioNotifications, getStudioUnreadCount, markStudioNotificationRead } from '../src/services/studioNotificationsService.js';

test('studio notification requests use bearer auth and handle a no-content mark-read response', async (t) => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({ url, ...options });
    return options.method === 'PATCH' ? new Response(null, { status: 204 }) : new Response(JSON.stringify(url.endsWith('unread-count') ? { unreadCount: 2 } : [{ id: 'notice', isRead: false }]));
  });
  assert.equal((await getStudioNotifications('studio-token'))[0].isRead, false);
  assert.equal((await getStudioUnreadCount('studio-token')).unreadCount, 2);
  assert.equal(await markStudioNotificationRead('studio-token', 'notice'), null);
  assert.deepEqual(calls.map(c => c.url), ['/api/studio/notifications', '/api/studio/notifications/unread-count', '/api/studio/notifications/notice/read']);
  assert.ok(calls.every(c => c.headers.Authorization === 'Bearer studio-token'));
  assert.equal(calls[2].method, 'PATCH');
});

test('notification failures allow the UI to report auth, ownership and network errors', async (t) => {
  const mock = t.mock.method(globalThis, 'fetch', async () => new Response('{}', { status: 401 }));
  await assert.rejects(getStudioNotifications('expired'), /session has expired/);
  mock.mock.mockImplementation(async () => new Response('{}', { status: 403 }));
  await assert.rejects(getStudioNotifications('customer-token'), /permission/);
  mock.mock.mockImplementation(async () => new Response(JSON.stringify({ message: 'Notification not found.' }), { status: 404 }));
  await assert.rejects(markStudioNotificationRead('token', 'another-studio'), /Notification not found/);
  mock.mock.mockImplementation(async () => { throw new Error('offline'); });
  await assert.rejects(getStudioUnreadCount('token'), /Unable to connect/);
});
