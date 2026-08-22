import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { SnapshotBuilder } from "../snapshot.js";

function makeTempDir(prefix = "azul-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test("SnapshotBuilder creates folders and script instances correctly", async () => {
  const tmp = makeTempDir();
  const src = path.join(tmp, "src");
  fs.mkdirSync(path.join(src, "ReplicatedStorage", "Modules"), {
    recursive: true,
  });
  const scriptPath = path.join(
    src,
    "ReplicatedStorage",
    "Modules",
    "Foo.server.lua",
  );
  fs.writeFileSync(scriptPath, "print('hello')", "utf8");

  const builder = new SnapshotBuilder({ sourceDir: src });
  const instances = await builder.build();

  const folderPaths = instances
    .filter((i) => i.className === "Folder")
    .map((i) => i.path.join("/"));
  assert.ok(folderPaths.includes("ReplicatedStorage"));
  assert.ok(folderPaths.includes("ReplicatedStorage/Modules"));

  const script = instances.find((i) => i.name === "Foo");
  assert.ok(script, "script instance present");
  assert.strictEqual(script?.className, "Script");
  assert.strictEqual(script?.path.join("/"), "ReplicatedStorage/Modules/Foo");

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("SnapshotBuilder rewrites @self/ using the instance name (non-Rojo push)", async () => {
  const tmp = makeTempDir();
  const src = path.join(tmp, "src", "ReplicatedStorage");

  // Azul peer pattern: Foo.luau sits next to a Foo/ folder holding its children.
  fs.mkdirSync(path.join(src, "Foo"), { recursive: true });
  fs.writeFileSync(
    path.join(src, "Foo.luau"),
    'local Bar = require("@self/Bar")',
    "utf8",
  );
  fs.writeFileSync(path.join(src, "Foo", "Bar.luau"), "return {}", "utf8");

  // Class suffixes must not leak into the require path (Baz.server -> Baz).
  fs.mkdirSync(path.join(src, "Baz"), { recursive: true });
  fs.writeFileSync(
    path.join(src, "Baz.server.lua"),
    'local Qux = require("@self/Qux")',
    "utf8",
  );
  fs.writeFileSync(path.join(src, "Baz", "Qux.luau"), "return {}", "utf8");

  const builder = new SnapshotBuilder({ sourceDir: path.join(tmp, "src") });
  const instances = await builder.build();

  const foo = instances.find((i) => i.name === "Foo");
  assert.strictEqual(foo?.source, 'local Bar = require("./Foo/Bar")');
  assert.ok(
    instances.some(
      (i) => i.path.join("/") === "ReplicatedStorage/Foo/Bar",
    ),
    "the rewritten path points at a real instance",
  );

  const baz = instances.find((i) => i.name === "Baz");
  assert.strictEqual(baz?.source, 'local Qux = require("./Baz/Qux")');

  fs.rmSync(tmp, { recursive: true, force: true });
});
