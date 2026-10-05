import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'vite';
import { JSDOM } from 'jsdom';
import { createElement, act } from 'react';
import * as service from '../src/services/adminService.js';

const output = resolve('node_modules/.cache/admin-monitoring-tests');
const source = resolve('src').replaceAll('\\', '/');
await build({ logLevel: 'silent', plugins: [{ name: 'admin-test-entry',
  resolveId(id) { if (id.replaceAll('\\', '/').endsWith('/admin-test-entry') || id === 'admin-test-entry') return '\0admin-test-entry'; },
  load(id) { if (id === '\0admin-test-entry') return `export { default as Admin } from '${source}/pages/Admin/AdminDashboard.jsx'; export { default as ProtectedRoute } from '${source}/components/auth/ProtectedRoute.jsx'; export { AuthContext } from '${source}/context/authContextValue.js'; export { default as App } from '${source}/app.jsx';`; },
}], build: { ssr: 'admin-test-entry', outDir: output, emptyOutDir: false,
  rollupOptions: { output: { entryFileNames: 'views.mjs' } } } });


const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'http://localhost/admin/dashboard' });
const navigation = [];
let pathname = '/admin/dashboard';
globalThis.window = new Proxy(dom.window, { get(target, key) {
  if (key === 'location') return { pathname, replace: path => navigation.push(path), assign: path => navigation.push(path) };
  return Reflect.get(target, key, target);
} });
globalThis.document = dom.window.document;
globalThis.HTMLElement = dom.window.HTMLElement;
globalThis.sessionStorage = dom.window.sessionStorage;
globalThis.localStorage = dom.window.localStorage;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
const { createRoot } = await import('react-dom/client');
const { Admin, ProtectedRoute, AuthContext, App } = await import(pathToFileURL(resolve(output, 'views.mjs')).href);

const originalFetch = globalThis.fetch;
let root;
const admin = { token: 'admin-jwt', user: { role: 'Admin', fullName: 'Platform Admin' }, isAuthenticated: true, logout() {} };
const page = (items = [], number = 1, count = items.length) => ({ items, page: number, pageSize: 10, totalCount: count, totalPages: Math.ceil(count / 10) });
const booking = { id: 25, customerName: 'Customer One', studioName: 'Snap Studio', packageName: 'Wedding', bookingDate: '2026-10-20', status: 'Pending', totalPrice: 5000 };
const dashboard = { totalStudios: 0, totalCustomers: 0, totalBookings: 0, totalPackages: 0, totalReviews: 0, bookingStatuses: [], recentBookings: [], recentStudios: [] };
const text = () => document.body.textContent;
const button = name => [...document.querySelectorAll('button')].find(element => element.textContent.trim() === name);
async function settle() { await act(async () => { await new Promise(resolve => setTimeout(resolve, 0)); }); }
async function render(component, auth = admin) {
  await act(async () => { root.render(createElement(AuthContext.Provider, { value: auth }, component)); });
  await settle();
}
async function click(element) {
  assert.ok(element, 'control exists');
  await act(async () => { element.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await settle();
}
async function input(element, value) {
  assert.ok(element, 'input exists');
  const prototype = element.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(prototype, 'value').set.call(element, value);
    element.dispatchEvent(new dom.window.Event(element.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
}
test.beforeEach(() => {
  navigation.length = 0; pathname = '/admin/dashboard'; sessionStorage.clear(); localStorage.clear();
  root = createRoot(document.getElementById('root'));
});
test.afterEach(async () => {
  await act(async () => root.unmount());
  globalThis.fetch = originalFetch;
});

test('route protection permits Admin and redirects anonymous, Customer and Studio', async () => {
  const child = createElement('p', null, 'Protected Admin content');
  await render(createElement(ProtectedRoute, { allowedRoles: ['Admin'] }, child));
  assert.ok(text().includes('Protected Admin content'));
  for (const [auth, destination] of [
    [{ ...admin, isAuthenticated: false }, '/auth'],
    [{ ...admin, user: { role: 'Customer' } }, '/customer'],
    [{ ...admin, user: { role: 'Studio' } }, '/studio'],
  ]) {
    await render(createElement(ProtectedRoute, { allowedRoles: ['Admin'] }, child), auth);
    assert.equal(navigation.at(-1), destination);
    assert.ok(!text().includes('Protected Admin content'));
  }
});

test('service sends only GET with bearer authentication and all server filters', async () => {
  globalThis.fetch = async (url, options) => {
    const params = new URL(url, 'http://localhost').searchParams;
    for (const [key, value] of Object.entries({ search: 'wedding', status: 'Pending', studioId: 'studio', customerId: '3', fromDate: '2026-10-01', toDate: '2026-10-31', page: '2', pageSize: '20' })) assert.equal(params.get(key), value);
    assert.equal(options.method, 'GET'); assert.equal(options.headers.Authorization, 'Bearer admin-jwt');
    return Response.json(page());
  };
  await service.getAdminBookings('admin-jwt', { search: 'wedding', status: 'Pending', studioId: 'studio', customerId: 3, fromDate: '2026-10-01', toDate: '2026-10-31', page: 2, pageSize: 20 });
});

test('missing authentication and HTTP errors do not expose backend content', async () => {
  let calls = 0;
  globalThis.fetch = async () => { calls++; return new Response('PRIVATE stack JWT connection string', { status: 403 }); };
  await assert.rejects(service.getAdminDashboard(''), /sign in/); assert.equal(calls, 0);
  for (const status of [400, 401, 403, 404, 500]) {
    globalThis.fetch = async () => new Response('PRIVATE stack JWT connection string', { status });
    await assert.rejects(service.getAdminDashboard('jwt'), error => !error.message.includes('PRIVATE'));
  }
});

test('dashboard renders loading, retry, empty data and refresh', async () => {
  let finish;
  globalThis.fetch = () => new Promise(resolve => { finish = resolve; });
  await render(createElement(Admin));
  assert.ok(document.querySelector('[role="status"]')); assert.ok(text().includes('Loading platform data'));
  await act(async () => finish(new Response('', { status: 500 }))); await settle();
  assert.ok(document.querySelector('[role="alert"]')); assert.ok(button('Retry'));
  let calls = 0;
  globalThis.fetch = async () => { calls++; return Response.json(dashboard); };
  await click(button('Retry'));
  assert.ok(text().includes('No bookings yet')); assert.ok(text().includes('No studios registered')); assert.ok(text().includes('Studio summaries')); assert.ok(!text().includes('Recent studios'));
  await click(button('Refresh')); assert.equal(calls, 2);
});

test('booking controls submit filters once, reset page, paginate and navigate to details', async () => {
  const calls = [];
  globalThis.fetch = async url => {
    calls.push(url);
    if (url.startsWith('/api/admin/studios')) return Response.json(page([{ id: 'studio-1', studioName: 'Snap Studio', ownerName: 'Owner' }]));
    const current = Number(new URL(url, 'http://localhost').searchParams.get('page') || 1);
    return Response.json(page([booking], current, 25));
  };
  await render(createElement(Admin, { page: 'bookings' }));
  const before = calls.length;
  await input(document.querySelector('[aria-label="Search bookings"]'), 'wedding');
  assert.equal(calls.length, before, 'typing does not dispatch');
  await input(document.querySelector('[aria-label="Filter booking status"]'), 'Pending');
  await input(document.querySelector('[aria-label="Filter studio"]'), 'studio-1');
  const dates = document.querySelectorAll('input[type="date"]');
  await input(dates[0], '2026-10-01'); await input(dates[1], '2026-10-31');
  await click(button('Search'));
  let params = new URL(calls.at(-1), 'http://localhost').searchParams;
  for (const [key, value] of Object.entries({ search: 'wedding', status: 'Pending', studioId: 'studio-1', fromDate: '2026-10-01', toDate: '2026-10-31', page: '1' })) assert.equal(params.get(key), value);
  assert.ok(text().includes('25 results')); assert.ok(text().includes('LKR')); assert.ok(!text().includes('USD'));
  assert.equal(document.querySelector('a[href="/admin/bookings/25"]').textContent, '#25');
  await click(document.querySelector('.admin-table tbody tr')); assert.equal(navigation.at(-1), '/admin/bookings/25');
  await click(document.querySelector('.admin-panel .admin-pagination button:last-child')); params = new URL(calls.at(-1), 'http://localhost').searchParams; assert.equal(params.get('page'), '2');
  await click(button('Clear filters')); params = new URL(calls.at(-1), 'http://localhost').searchParams;
  assert.equal(params.get('page'), '1'); assert.equal(params.has('search'), false); assert.equal(params.has('status'), false); assert.equal(params.has('studioId'), false);
});

test('booking invalid date range blocks dispatch and collection errors retry', async () => {
  let calls = 0;
  globalThis.fetch = async url => { if (url.includes('/studios')) return Response.json(page()); calls++; return new Response('', { status: 500 }); };
  await render(createElement(Admin, { page: 'bookings' }));
  assert.ok(button('Retry'));
  globalThis.fetch = async () => { calls++; return Response.json(page()); };
  await click(button('Retry')); assert.ok(text().includes('No bookings found'));
  const before = calls;
  const dates = document.querySelectorAll('input[type="date"]');
  await input(dates[0], '2026-10-31'); await input(dates[1], '2026-10-01'); await click(button('Search'));
  assert.equal(calls, before); assert.ok(text().includes('From date must not exceed to date'));
});

test('booking details render notes and readable pricing without raw snapshot fields', async () => {
  globalThis.fetch = async () => Response.json({ ...booking, customerEmail: 'customer@test', startTime: '10:00', endTime: '12:00', notes: 'Outdoor shoot', statusHistory: [],
    pricingSnapshotJson: JSON.stringify({ BasePrice: 4000, SelectedAddons: [{ Name: 'Album', Price: 1000 }], ExtraHours: 0, ExtraHoursCost: 0, AdditionalPhotographers: 0, AdditionalPhotographersCost: 0, FinalPrice: 5000, InternalToken: 'PRIVATE' }) });
  await render(createElement(Admin, { page: 'booking', id: '25' }));
  for (const value of ['Outdoor shoot', 'Base price', 'Album', 'Final price', 'LKR', 'No status history']) assert.ok(text().includes(value), value);
  assert.ok(!text().includes('PRIVATE')); assert.ok(!text().includes('BasePrice')); assert.ok(!text().includes('InternalToken'));
  for (const name of ['Approve', 'Reject', 'Cancel', 'Delete', 'Edit']) assert.equal(button(name), undefined);
});

for (const kind of ['studios', 'customers', 'reviews']) test(`${kind} preserve empty states, server pagination and filters`, async () => {
  const calls = [];
  globalThis.fetch = async url => { calls.push(url); return Response.json(page()); };
  await render(createElement(Admin, { page: kind }));
  assert.ok(text().includes(`No ${kind} found`)); assert.ok(text().includes('0 results')); assert.equal(button('Next').disabled, true);
  await input(document.querySelector(`[aria-label="Search ${kind}"]`), 'Colombo');
  if (kind === 'reviews') await input(document.querySelector('[aria-label="Filter rating"]'), '5');
  assert.equal(calls.length, 1); await click(button('Search'));
  const params = new URL(calls.at(-1), 'http://localhost').searchParams;
  assert.equal(params.get('search'), 'Colombo'); if (kind === 'reviews') assert.equal(params.get('rating'), '5');
});

test('workflow monitoring uses existing GET endpoints and never presents approval controls', async () => {
  const calls = [];
  const workflow = { id: 'workflow-1', status: 'AwaitingApproval', currentStep: 'HumanApproval', proposalVersion: 1,
    monitoring: { customerName: 'Customer One', studioName: 'Snap Studio', events: [{ id: 'event-1', eventType: 'ProposalPublished', stage: 'Validation', success: true, createdAt: '2026-10-01' }] } };
  globalThis.fetch = async (url, options) => { calls.push(url); assert.equal(options.method, 'GET'); return Response.json(url === '/api/ai-workflows/workflow-1' ? workflow : { items: [workflow], page: 1, pageSize: 20, hasMore: false }); };
  await render(createElement(Admin, { page: 'workflows' }));
  assert.ok(document.querySelector('a[href="/admin/workflows/workflow-1"]')); assert.equal(button('Next').disabled, true);
  await render(createElement(Admin, { page: 'workflow', id: 'workflow-1' }));
  assert.ok(calls.includes('/api/ai-workflows/workflow-1')); assert.ok(text().includes('Proposal Published')); assert.ok(text().includes('Customer One'));
  assert.equal(button('Approve'), undefined); assert.equal(button('Reject'), undefined);
});

test('actual Admin route selects booking monitoring and rejects Studio authentication', async () => {
  pathname = '/admin/bookings';
  globalThis.fetch = async () => Response.json(page());
  const token = `header.${Buffer.from(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.signature`;
  sessionStorage.setItem('authToken', token); sessionStorage.setItem('authUser', JSON.stringify({ role: 'Admin' }));
  await act(async () => root.render(createElement(App)));
  assert.ok(document.querySelector('[aria-label="Search bookings"]'));
  await act(async () => root.unmount()); root = createRoot(document.getElementById('root'));
  sessionStorage.setItem('authUser', JSON.stringify({ role: 'Studio' }));
  await act(async () => root.render(createElement(App)));
  assert.equal(navigation.at(-1), '/studio'); assert.equal(document.querySelector('[aria-label="Search bookings"]'), null);
});

test.after(() => dom.window.close());
