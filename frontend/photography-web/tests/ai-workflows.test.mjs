import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'vite';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { getWorkflow, listWorkflows, parseWorkflow, reviewWorkflow } from '../src/services/aiWorkflowService.js';

const id = '11111111-1111-4111-8111-111111111111';
const studio = '22222222-2222-4222-8222-222222222222';
const pack = '33333333-3333-4333-8333-333333333333';
function fixture(status = 'AwaitingApproval') {
  return { id, status, currentStep: 'HumanApproval', proposalVersion: 3, selectedStudioId: studio, selectedPackageId: pack,
    expiresAt: '2030-01-01T12:00:00Z', privateEvents: 'PRIVATE', proposal: { version: 3,
      selection: { studioId: studio, packageId: pack, date: '2030-01-01', startTime: '10:00:00', endTime: '12:00:00', customization: { extraHours: 0, additionalPhotographers: 0 } },
      pricing: { packageName: 'Portrait session', finalPrice: 5000, selectedAddons: [] },
      requirements: { photographyType: 'Portrait', location: 'Colombo', maximumBudget: 6000, coverageHours: 2, earliestDate: '2030-01-01', latestDate: '2030-01-02', requestedServices: ['Photography'] },
      finalEvidence: { evidenceId: 'PRIVATE', prompt: 'PRIVATE' } } };
}
const originalFetch = globalThis.fetch;
test.afterEach(() => { globalThis.fetch = originalFetch; });

test('Studio queue uses JWT, bounded pagination and status; projects safe fields', async () => {
  globalThis.fetch = async (url, options) => {
    assert.equal(url, '/api/ai-workflows?page=2&pageSize=20&status=AwaitingApproval');
    assert.equal(options.headers.Authorization, 'Bearer studio-jwt');
    assert.equal(options.method, 'GET');
    return Response.json({ items: [fixture()], page: 2, hasMore: false });
  };
  const page = await listWorkflows('studio-jwt', { page: 2 });
  assert.equal(page.items[0].proposal.packageName, 'Portrait session');
  assert.ok(!JSON.stringify(page).includes('PRIVATE'));
});
test('details use fixed ASP.NET path and verify correlation', async () => {
  globalThis.fetch = async url => { assert.equal(url, `/api/ai-workflows/${id}`); return Response.json(fixture()); };
  assert.equal((await getWorkflow('jwt', id)).id, id);
  globalThis.fetch = async () => Response.json({ ...fixture(), id: studio });
  await assert.rejects(getWorkflow('jwt', id));
});
for (const decision of ['approve', 'reject']) test(`${decision} sends only permitted review fields`, async () => {
  globalThis.fetch = async (url, options) => {
    assert.equal(url, `/api/ai-workflows/${id}/${decision}`);
    assert.equal(options.headers.Authorization, 'Bearer studio-jwt');
    assert.deepEqual(JSON.parse(options.body), decision === 'approve' ? { proposalVersion: 3 } : { proposalVersion: 3, reason: 'Unavailable' });
    return Response.json({ workflowId: id, proposalVersion: 3, status: decision === 'approve' ? 'Approved' : 'Rejected' });
  };
  await reviewWorkflow('studio-jwt', parseWorkflow(fixture()), decision, 'Unavailable');
});
test('RevalidationRequired remains distinct from approval', async () => {
  globalThis.fetch = async () => Response.json({ workflowId: id, proposalVersion: 3, status: 'RevalidationRequired' });
  assert.equal(await reviewWorkflow('jwt', parseWorkflow(fixture()), 'approve'), 'RevalidationRequired');
});
for (const reason of ['', ' ', 'x'.repeat(1001)]) test(`invalid rejection reason length ${reason.length} is blocked`, async () => {
  globalThis.fetch = () => { throw new Error('Must not dispatch'); };
  await assert.rejects(reviewWorkflow('jwt', parseWorkflow(fixture()), 'reject', reason), /1,000/);
});
test('non-awaiting decisions and missing JWT never dispatch', async () => {
  let calls = 0; globalThis.fetch = () => { calls++; throw new Error('Must not dispatch'); };
  await assert.rejects(reviewWorkflow('jwt', parseWorkflow(fixture('Approved')), 'approve'));
  await assert.rejects(listWorkflows(''));
  assert.equal(calls, 0);
});
for (const status of [400, 401, 403, 404, 409, 500]) test(`HTTP ${status} errors hide backend content`, async () => {
  globalThis.fetch = async () => new Response('PRIVATE stack token', { status });
  await assert.rejects(getWorkflow('jwt', id), error => !error.message.includes('PRIVATE'));
});
test('malformed and unknown responses fail closed', async () => {
  for (const data of [{}, { ...fixture(), status: 'Unknown' }, { ...fixture(), proposal: null }]) {
    globalThis.fetch = async () => Response.json(data);
    await assert.rejects(getWorkflow('jwt', id));
  }
});

// Render the real JSX view using the existing Vite toolchain; no new test dependencies.
const output = resolve('node_modules/.cache/ai-workflow-tests');
await build({ logLevel: 'silent', build: { ssr: 'src/pages/Studio/AiWorkflowView.jsx', outDir: output,
  emptyOutDir: false, rollupOptions: { output: { entryFileNames: 'view.mjs' } } } });
const { default: View } = await import(pathToFileURL(resolve(output, 'view.mjs')).href);
for (const status of ['AwaitingApproval', 'Approved', 'Rejected', 'RevalidationRequired', 'Failed']) test(`render canonical details and ${status} review controls`, () => {
  const html = renderToStaticMarkup(createElement(View, { workflow: parseWorkflow(fixture(status)), studioName: 'Snap Studio',
    onApprove() {}, onReject() {}, onReason() {}, reason: 'Unavailable' }));
  for (const text of ['Snap Studio', 'Portrait session', '2030-01-01', '10:00', '12:00', 'Colombo', 'Photography', 'LKR', 'version 3']) assert.ok(html.includes(text), text);
  assert.equal(html.includes('>Approve</button>'), status === 'AwaitingApproval');
  assert.equal(html.includes('>Reject</button>'), status === 'AwaitingApproval');
  assert.ok(!html.includes('PRIVATE'));
  if (status === 'RevalidationRequired') assert.ok(html.includes('availability or pricing has changed'));
  if (status === 'Approved') assert.ok(html.includes('A booking has not been created'));
});
test('review controls disabled while request pending', () => {
  const html = renderToStaticMarkup(createElement(View, { workflow: parseWorkflow(fixture()), busy: true,
    reason: 'Unavailable', onApprove() {}, onReject() {}, onReason() {} }));
  assert.match(html, /disabled="">Approve/);
  assert.match(html, /disabled="">Reject/);
});
