import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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
