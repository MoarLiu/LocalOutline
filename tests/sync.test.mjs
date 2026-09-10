import assert from "node:assert/strict";
import test from "node:test";
import { createSyncStore } from "../server/sync-store.mjs";
import { loadTypescript } from "./helpers/typescript.mjs";

const sync = loadTypescript("src/sync.ts");
const { migrateDocument } = loadTypescript("src/migrations.ts");
const config = { serverUrl: "http://fixture.invalid", token: "fixture", autoSync: false, autoSyncIntervalSeconds: 60 };
const document = (id, text, updatedAt = "2026-09-01T00:00:00.000Z") => migrateDocument({
  id, title: id, createdAt: updatedAt, updatedAt, nodes: [{ id: `node-${id}`, text, children: [] }],
});

async function fixture(t) {
  const store = await createSyncStore(":memory:");
  const originalWindow = globalThis.window;
  let fail = () => false;
  globalThis.window = { bike: { invokeSyncRequest: async (request) => {
    const { pathname, method, body } = request;
    if (fail(request)) return { ok: false, status: 503, data: { message: "injected failure" } };
    try {
      const id = decodeURIComponent(pathname.split("/")[3]);
      const data = pathname === "/api/sync/manifest"
        ? method === "GET" ? store.getManifest() : store.patchManifest(body)
        : method === "GET" ? store.getDocument(id)
          : method === "PUT" ? store.putDocument({ id, ...body }) : store.deleteDocument({ id, ...body });
      return { ok: true, status: 200, data };
    } catch (error) {
      return { ok: false, status: error.statusCode || 500, data: { message: error.message } };
    }
  } } };
  t.after(() => { store.close(); globalThis.window = originalWindow; });
  return { store, failWhen: (predicate) => { fail = predicate; } };
}

test("failed sync checkpoints uploads without acknowledging an unapplied new download", async (t) => {
  const { store, failWhen } = await fixture(t);
  const a = document("A", "remote only", "2026-09-02T00:00:00.000Z");
  const b = document("B", "base");
  store.putDocument({ id: "A", expectedRevision: null, document: a });
  store.putDocument({ id: "B", expectedRevision: null, document: b });
  const workspace = { version: 1, activeDocumentId: "B", documents: [document("B", "edited"), document("C", "new")] };
  let checkpoint = sync.emptySyncState(config.serverUrl);
  checkpoint.documentRevisions.B = 1;
  checkpoint.documentFingerprints.B = sync.documentFingerprint(b);
  failWhen(({ method, pathname }) => method === "PUT" && pathname.endsWith("/C"));
  await assert.rejects(sync.syncWorkspaceWithRemote(workspace, config, checkpoint, {
    onCheckpoint: (state) => { checkpoint = state; },
  }), /injected failure/);
  assert.equal(checkpoint.documentRevisions.A, undefined);
  assert.equal(checkpoint.documentRevisions.B, 2);
  failWhen(() => false);
  const retried = await sync.syncWorkspaceWithRemote(workspace, config, checkpoint);
  assert.equal(store.getDocument("A").deletedAt, null);
  assert.ok(retried.workspace.documents.some((item) => item.id === "A"));
  assert.equal(retried.summary.deleted, 0);
  assert.deepEqual(retried.summary.conflicts, []);
});

test("failed sync keeps the old baseline for a downloaded update", async (t) => {
  const { store, failWhen } = await fixture(t);
  const a = document("A", "base");
  store.putDocument({ id: "A", expectedRevision: null, document: a });
  store.putDocument({ id: "A", expectedRevision: 1, document: document("A", "remote edit") });
  const workspace = { version: 1, activeDocumentId: "A", documents: [a, document("B", "new")] };
  let checkpoint = sync.emptySyncState(config.serverUrl);
  checkpoint.documentRevisions.A = 1;
  checkpoint.documentFingerprints.A = sync.documentFingerprint(a);
  failWhen(({ method }) => method === "PATCH");
  await assert.rejects(sync.syncWorkspaceWithRemote(workspace, config, checkpoint, {
    onCheckpoint: (state) => { checkpoint = state; },
  }), /injected failure/);
  assert.equal(checkpoint.documentRevisions.A, 1);
  assert.equal(checkpoint.documentRevisions.B, 1);
  failWhen(() => false);
  const retried = await sync.syncWorkspaceWithRemote(workspace, config, checkpoint);
  assert.equal(retried.workspace.documents.find((item) => item.id === "A").nodes[0].text, "remote edit");
  assert.deepEqual(retried.summary.conflicts, []);
});

test("delete checkpoints exclude earlier downloads", async (t) => {
  const { store, failWhen } = await fixture(t);
  store.putDocument({ id: "A", expectedRevision: null, document: document("A", "remote", "2026-09-02T00:00:00.000Z") });
  store.putDocument({ id: "B", expectedRevision: null, document: document("B", "deleted locally") });
  const workspace = { version: 1, activeDocumentId: "C", documents: [document("C", "local")] };
  let checkpoint = sync.emptySyncState(config.serverUrl);
  checkpoint.documentRevisions.B = 1;
  failWhen(({ method, pathname }) => method === "PUT" && pathname.endsWith("/C"));
  await assert.rejects(sync.syncWorkspaceWithRemote(workspace, config, checkpoint, {
    onCheckpoint: (state) => { checkpoint = state; },
  }), /injected failure/);
  assert.equal(checkpoint.documentRevisions.A, undefined);
  assert.equal(checkpoint.deletedDocumentRevisions.B, 2);
});

test("desktop sync preserves mobile shortcuts and document/node extensions", async (t) => {
  const { store } = await fixture(t);
  const source = { ...document("A", "mobile"), isShortcut: true, extension: { keep: true } };
  source.nodes[0].extension = ["keep"];
  store.putDocument({ id: "A", expectedRevision: null, document: source });
  const pulled = await sync.pullWorkspaceFromRemote(config);
  const edited = { ...pulled.workspace, extension: "workspace", documents: pulled.workspace.documents.map((item) => ({ ...item, title: "desktop edit" })) };
  const result = await sync.syncWorkspaceWithRemote(edited, config, pulled.state);
  const remote = store.getDocument("A").document;
  assert.equal(remote.isShortcut, true);
  assert.deepEqual(remote.extension, { keep: true });
  assert.deepEqual(remote.nodes[0].extension, ["keep"]);
  assert.equal(result.workspace.extension, "workspace");
});
