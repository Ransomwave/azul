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

  // Add properties to instance and pack
  foo!.properties = { MyProp: 123 };
  const index = loadSourcemapPropertyIndex(smPath);
  const applied = applySourcemapProperties(instances!, index);
  assert.strictEqual(typeof applied, "number");

  fs.rmSync(tmp, { recursive: true, force: true });
});
