import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createServer } from "vite";

const vite = await createServer({ configFile: false, server: { middlewareMode: true }, appType: "custom" });
after(() => vite.close());
const { createPhotographyPackage } = await vite.ssrLoadModule("/src/services/photographyPackagesService.js");
const sample = {
  name: "Wedding Premium", description: "", basePrice: "150000", durationHours: "8",
  numberOfPhotographers: "2", editedPhotoCount: "200", extraHourRate: "0",
  additionalPhotographerRate: "0", status: "Active", albumIncluded: false,
  videoIncluded: false, serviceIds: [randomUUID()],
};

test("package POST sends numeric form values using the exact DTO property names", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async (url, options) => {
    calls++;
    assert.equal(url, "/api/studio/packages");
    assert.equal(options.method, "POST");
    assert.equal(options.headers.has("Content-Type"), false);
    assert.ok(options.body instanceof FormData);
    assert.deepEqual(Object.fromEntries(options.body), {
      Name: "Wedding Premium", Description: "", BasePrice: "150000", DurationHours: "8",
      NumberOfPhotographers: "2", EditedPhotoCount: "200", ExtraHourRate: "0",
      AdditionalPhotographerRate: "0", Status: "Active", AlbumIncluded: "false",
      VideoIncluded: "false", ServiceIds: sample.serviceIds[0],
    });
    return Response.json({ name: sample.name, durationHours: 8 }, { status: 201 });
  });
  const result = await createPhotographyPackage(undefined, sample);
  assert.equal(result.durationHours, 8);
  assert.equal(calls, 1);
});

test("missing, zero, and invalid duration never reach fetch", (t) => {
  const fetch = t.mock.method(globalThis, "fetch", () => { throw new Error("Unexpected request"); });
  for (const durationHours of [undefined, null, "", " ", "0", 0, -1, "eight", NaN, Infinity]) {
    assert.throws(() => createPhotographyPackage(undefined, { ...sample, durationHours }), /Duration must be greater than zero/);
  }
  assert.equal(fetch.mock.callCount(), 0);
});
