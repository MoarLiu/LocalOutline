import assert from "node:assert/strict";
import test from "node:test";
import { loadTypescript } from "./helpers/typescript.mjs";

const { migrateWorkspace } = loadTypescript("src/migrations.ts");

test("workspace migration retains extensions while validating known fields", () => {
  const workspace = migrateWorkspace({
    version: 1, activeDocumentId: "doc", extension: { keep: true },
    documents: [{
      id: "doc", title: "Document", isShortcut: true, extension: "document",
      markdownSource: 42, markdownUpdatedAt: false,
      nodes: [{ id: "node", text: "Text", checked: "true", color: "invalid", extension: [1, 2], children: [] }],
    }],
  });
  const restored = JSON.parse(JSON.stringify(workspace));
  assert.deepEqual(restored.extension, { keep: true });
  assert.equal(restored.documents[0].extension, "document");
  assert.equal(restored.documents[0].isShortcut, true);
  assert.equal(restored.documents[0].markdownSource, undefined);
  assert.equal(restored.documents[0].markdownUpdatedAt, undefined);
  assert.equal(restored.documents[0].nodes[0].checked, false);
  assert.equal(restored.documents[0].nodes[0].color, "plain");
  assert.deepEqual(restored.documents[0].nodes[0].extension, [1, 2]);
});
