import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { SnapshotBuilder } from "../snapshot.js";
import {
  buildInstancesFromSourcemap,
  applySourcemapProperties,
  loadSourcemapPropertyIndex,
} from "../sourcemap/propertyLoader.js";

function makeTempDir(prefix = "azul-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test("buildInstancesFromSourcemap reads file contents and applySourcemapProperties merges properties", async () => {
  const tmp = makeTempDir();
  const scriptFile = path.join(tmp, "script.luau");
  fs.writeFileSync(scriptFile, "print('smap')", "utf8");

  const sourcemap = {
    name: "Game",
    className: "DataModel",
    children: [
      {
        name: "ReplicatedStorage",
        className: "ReplicatedStorage",
        children: [
          {
            name: "ModuleA",
            className: "Folder",
            children: [
              {
                name: "Foo",
                className: "ModuleScript",
                guid: "g1",
                properties: { MyProp: 123 },
                attributes: { Build: "dev" },
                tags: ["Client"],
                filePaths: [scriptFile],
              },
            ],
          },
        ],
      },
    ],
  };

  const smPath = path.join(tmp, "sourcemap.json");
  fs.writeFileSync(smPath, JSON.stringify(sourcemap, null, 2), "utf8");

  const instances = buildInstancesFromSourcemap(smPath);
  assert.ok(instances && instances.length > 0, "instances built");
  const foo = instances!.find((i) => i.name === "Foo");
  assert.ok(foo?.source?.includes("smap"));

  // Clear fields so merge/write-back path must restore them from sourcemap index
  foo!.properties = undefined;
  foo!.attributes = undefined;
  foo!.tags = undefined;

  const index = loadSourcemapPropertyIndex(smPath);
  assert.ok(index, "property index loaded");
  const applied = applySourcemapProperties(instances!, index);
  assert.strictEqual(applied, 1);
  assert.deepStrictEqual(foo!.properties, { MyProp: 123 });
  assert.deepStrictEqual(foo!.attributes, { Build: "dev" });
  assert.deepStrictEqual(foo!.tags, ["Client"]);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("applySourcemapProperties matches same-named sibling scripts by file path", async () => {
  const tmp = makeTempDir();
  const syncDir = path.join(tmp, "sync");
  const serviceDir = path.join(syncDir, "ServerScriptService");
  fs.mkdirSync(serviceDir, { recursive: true });

  const fileA = path.join(serviceDir, "Script__3f9a2c1b.server.luau");
  const fileB = path.join(serviceDir, "Script__8d41e07a.server.luau");
  fs.writeFileSync(fileA, "print('round loop')", "utf8");
  fs.writeFileSync(fileB, "print('old test')", "utf8");

  const sourcemap = {
    name: "Game",
    className: "DataModel",
    children: [
      {
        name: "ServerScriptService",
        className: "ServerScriptService",
        children: [
          {
            name: "Script",
            className: "Script",
            guid: "a",
            properties: { Enabled: true },
            attributes: { RoundLength: 120 },
            filePaths: [fileA],
          },
          {
            name: "Script",
            className: "Script",
            guid: "b",
            properties: { Enabled: false },
            filePaths: [fileB],
          },
        ],
      },
    ],
  };

  const smPath = path.join(tmp, "sourcemap.json");
  fs.writeFileSync(smPath, JSON.stringify(sourcemap), "utf8");

  const instances = await new SnapshotBuilder({ sourceDir: syncDir }).build();
  const applied = applySourcemapProperties(
    instances,
    loadSourcemapPropertyIndex(smPath),
  );
  assert.strictEqual(applied, 2);

  const a = instances.find((i) => i.source?.includes("round loop"));
  const b = instances.find((i) => i.source?.includes("old test"));
  assert.deepStrictEqual(a?.properties, { Enabled: true });
  assert.deepStrictEqual(a?.attributes, { RoundLength: 120 });
  assert.deepStrictEqual(b?.properties, { Enabled: false });
  assert.strictEqual(b?.attributes, undefined);

  fs.rmSync(tmp, { recursive: true, force: true });
});
