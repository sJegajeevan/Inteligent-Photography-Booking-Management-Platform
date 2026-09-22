import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createServer } from "vite";
import react from "@vitejs/plugin-react";

// Exercise the component's event handlers with deterministic hook state, without a browser.
const hooksId = "\0addon-test-hooks";
const vite = await createServer({
  configFile: false, server: { middlewareMode: true, hmr: false }, appType: "custom",
  plugins: [{
    name: "addon-test-hooks",
    resolveId(id) { if (id === "addon-test-hooks") return hooksId; },
    load(id) {
      if (id === hooksId) return `
        let slots = [], cursor = 0;
        export function reset() { slots = []; cursor = 0; }
        export function render(component, props) { cursor = 0; return component(props); }
        export function useState(initial) { const i = cursor++; if (!(i in slots)) slots[i] = initial; return [slots[i], value => { slots[i] = typeof value === 'function' ? value(slots[i]) : value; }]; }
        export function useRef(initial) { const [ref] = useState({ current: initial }); return ref; }
        export function useMemo(fn) { return fn(); }
      `;
    },
    transform(source, id) {
      if (id.endsWith("/StudioPackages.jsx")) return source.replace('from "react"', 'from "addon-test-hooks"');
    },
  }, react()],
});
after(() => vite.close());
const hooks = await vite.ssrLoadModule("addon-test-hooks");
const { default: StudioPackages } = await vite.ssrLoadModule("/src/pages/Studio/StudioPackages.jsx");
const api = await vite.ssrLoadModule("/src/services/packageAddonsService.js");

function nodes(tree) {
  if (!tree || typeof tree !== "object") return [];
  if (Array.isArray(tree)) return tree.flatMap(nodes);
  return [tree, ...nodes(tree.props?.children)];
}
const find = (tree, predicate) => { const node = nodes(tree).find(predicate); assert.ok(node, "Expected UI element"); return node; };
const button = (tree, text) => find(tree, n => n.props?.children === text && n.props?.onClick);
const panel = tree => find(tree, n => n.props?.title?.endsWith(" Add-ons"));
const list = tree => find(panel(tree), n => Array.isArray(n.props?.addons));
const form = tree => find(panel(tree), n => n.props?.className === "addon-form");
function fill(tree, name, price) {
  const inputs = nodes(form(tree)).filter(n => n.type === "input");
  inputs[0].props.onChange({ target: { value: name } });
  inputs[1].props.onChange({ target: { value: price } });
}
function fixture() {
  hooks.reset();
  const packages = ["Silver Package", "Second Package"].map(name => ({ id: randomUUID(), name, status: "Active", addons: [], services: [] }));
  const props = {
    packages, services: [],
    onLoadAddons: id => api.getPackageAddons(undefined, id),
    onCreateAddon: (id, value) => api.createPackageAddon(undefined, id, value),
    onUpdateAddon: (id, addonId, value) => api.updatePackageAddon(undefined, id, addonId, value),
    onDeleteAddon: (id, addonId) => api.deletePackageAddon(undefined, id, addonId),
  };
  const render = () => hooks.render(StudioPackages, props);
  const open = index => nodes(render()).filter(n => n.type === "button" && n.props?.children === "Add-ons")[index].props.onClick();
  return { packages, props, render, open };
}

test("two packages keep CRUD routes and refreshed add-on lists separate", async t => {
  const { packages, render, open } = fixture();
  const records = new Map(packages.map(p => [p.id, []]));
  const calls = [];
  t.mock.method(globalThis, "fetch", async (url, options) => {
    const match = /^\/api\/studio\/packages\/([^/]+)\/addons(?:\/([^/]+))?$/.exec(url);
    assert.ok(match);
    const [, packageId, addonId] = match;
    assert.ok(records.has(packageId));
    const method = options.method || "GET";
    calls.push([method, packageId]);
    const rows = records.get(packageId);
    if (method === "GET") return Response.json(rows);
    if (method === "DELETE") {
      assert.ok(rows.some(a => a.id === addonId));
      records.set(packageId, rows.filter(a => a.id !== addonId));
      return new Response(null, { status: 204 });
    }
    const value = JSON.parse(options.body);
    assert.equal(typeof value.price, "number");
    const saved = { ...value, id: addonId || randomUUID(), packageId };
    if (method === "POST") rows.push(saved);
    else { const i = rows.findIndex(a => a.id === addonId); assert.ok(i >= 0); rows[i] = saved; }
    return Response.json(saved, { status: method === "POST" ? 201 : 200 });
  });
  for (let i = 0; i < packages.length; i++) {
    await open(i);
    assert.deepEqual(list(render()).props.addons, []);
    fill(render(), `Addon ${i}`, "100");
    await form(render()).props.onSubmit({ preventDefault() {} });
    const saved = list(render()).props.addons[0];
    assert.equal(saved.packageId, packages[i].id);
    list(render()).props.onEdit(saved);
    fill(render(), `Edited ${i}`, "200");
    await form(render()).props.onSubmit({ preventDefault() {} });
    button(panel(render()), "Close").props.onClick();
    await open(i);
    assert.equal(list(render()).props.addons[0].name, `Edited ${i}`);
    assert.equal(nodes(form(render())).find(n => n.type === "input").props.value, "");
    button(panel(render()), "Close").props.onClick();
  }
  hooks.reset(); // Simulate a refresh: no component state survives, only server records.
  for (let i = 0; i < packages.length; i++) {
    await open(i);
    const rows = list(render()).props.addons;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].packageId, packages[i].id);
    list(render()).props.onDelete(rows[0]);
    const confirmation = find(render(), n => n.props?.title === "Delete add-on");
    await button(confirmation, "Delete add-on").props.onClick();
    assert.deepEqual(list(render()).props.addons, []);
    button(panel(render()), "Close").props.onClick();
    await open(i);
    assert.deepEqual(list(render()).props.addons, []);
    button(panel(render()), "Close").props.onClick();
    for (const method of ["GET", "POST", "PUT", "DELETE"]) assert.ok(calls.some(c => c[0] === method && c[1] === packages[i].id));
  }
});

test("late loads and creates cannot overwrite another package's modal", async () => {
  const { packages, props, render, open } = fixture();
  let resolveOldLoad;
  props.onLoadAddons = id => id === packages[0].id ? new Promise(resolve => { resolveOldLoad = resolve; }) : Promise.resolve([]);
  const oldLoad = open(0);
  button(panel(render()), "Close").props.onClick();
  await open(1);
  resolveOldLoad([{ id: randomUUID(), packageId: packages[0].id }]);
  await oldLoad;
  assert.deepEqual(list(render()).props.addons, []);
  let resolveCreate;
  props.onCreateAddon = (id, value) => {
    assert.equal(id, packages[1].id);
    return new Promise(resolve => { resolveCreate = () => resolve({ ...value, id: randomUUID(), packageId: id }); });
  };
  fill(render(), "Pending", "100");
  const pending = form(render()).props.onSubmit({ preventDefault() {} });
  button(panel(render()), "Close").props.onClick();
  props.onLoadAddons = async () => [];
  await open(0);
  resolveCreate();
  await pending;
  assert.deepEqual(list(render()).props.addons, []);
  assert.equal(panel(render()).props.title, "Silver Package Add-ons");
});

test("cards show only their own add-ons, three at most, and update with package data", () => {
  const { packages, props, render } = fixture();
  const text = node => {
    if (Array.isArray(node)) return node.map(text).join("");
    if (node == null || typeof node === "boolean") return "";
    return typeof node === "object" ? text(node.props?.children) : String(node);
  };
  const cards = () => nodes(render()).filter(n => n.props?.className === "package-included package-card-addons");
  const addon = (packageId, name, price) => ({ id: randomUUID(), packageId, name, price });
  packages[0].addons = Array.from({ length: 5 }, (_, i) => addon(packages[0].id, `Silver extra ${i}`, 18000 + i));
  packages[1].addons = [addon(packages[1].id, "Second package extra", 7500)];
  assert.match(text(cards()[0]), /Silver extra 0/);
  assert.match(text(cards()[0]), /LKR\s*18,000\.00/);
  assert.match(text(cards()[0]), /\+ 2 more/);
  assert.doesNotMatch(text(cards()[0]), /Silver extra 3|Second package extra/);
  assert.match(text(cards()[1]), /Second package extra/);
  assert.doesNotMatch(text(cards()[1]), /Silver extra/);
  props.packages = packages.map(p => p.id === packages[1].id ? { ...p, addons: [] } : p);
  assert.equal(text(cards()[1]), "Add-onsNo add-ons");
  assert.match(text(cards()[0]), /Silver extra 0/);
  props.packages = props.packages.map(p => p.id === packages[1].id ? { ...p, addons: [addon(p.id, "New extra", 500)] } : p);
  assert.match(text(cards()[1]), /New extra/);
  assert.doesNotMatch(text(cards()[0]), /New extra/);
});
