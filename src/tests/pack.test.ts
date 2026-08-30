import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { PackCommand } from "../pack.js";
import { config } from "../config.js";

// Use ephemeral IPC port to avoid collisions
config.port = 0;

function tmpDir(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test("PackCommand.buildSourcemap produces _azul metadata, packed properties, and filePaths", () => {
  const prevSyncDir = config.syncDir;
  const tmp = tmpDir("azul-pack-test-");
  config.syncDir = tmp;

  const pack = new PackCommand({});
  try {
    const snapshot = [
      {
        guid: "groot",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
      },
      {
        guid: "gmod",
        className: "Folder",
        name: "ModuleA",
        path: ["ReplicatedStorage", "ModuleA"],
        parentGuid: "groot",
      },
      {
        guid: "gfoo",
        className: "ModuleScript",
        name: "Foo",
        path: ["ReplicatedStorage", "ModuleA", "Foo"],
        parentGuid: "gmod",
        properties: { X: 1 },
        attributes: { A: true },
        tags: ["t"],
      },
    ];

    // Write the script file where FileWriter's naming scheme expects it, so
    // buildSourcemap can discover it without an existing sourcemap.json.
    const scriptDir = path.join(tmp, "ReplicatedStorage", "ModuleA");
    fs.mkdirSync(scriptDir, { recursive: true });
    fs.writeFileSync(
      path.join(scriptDir, `Foo${config.scriptExtension}`),
      "-- foo",
      "utf8",
    );

    const { sourcemap: root, packedCount } = (pack as any).buildSourcemap(
      snapshot,
      123456789,
    );
    assert.strictEqual(typeof root._azul?.packedAt, "string");
    assert.strictEqual(root._azul?.packVersion, 1);
    assert.strictEqual(root._azul?.placeId, 123456789);
    assert.strictEqual(packedCount, 1);

    // Unsaved places report PlaceId 0, which is not openable
    const { sourcemap: unsaved } = (pack as any).buildSourcemap(snapshot, 0);
    assert.strictEqual(unsaved._azul?.placeId, undefined);

    const moduleA = root.children[0].children[0];
    const foo = moduleA.children[0];
    assert.strictEqual(foo.name, "Foo");
    assert.deepStrictEqual(foo.properties, { X: 1 });
    assert.deepStrictEqual(foo.filePaths, [
      path
        .relative(
          process.cwd(),
          path.join(scriptDir, `Foo${config.scriptExtension}`),
        )
        .replace(/\\/g, "/"),
    ]);
  } finally {
    (pack as any).ipc.close();
    config.syncDir = prevSyncDir;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("PackCommand overwrites whatever is already at the output path instead of merging", () => {
  const prevSyncDir = config.syncDir;
  const tmp = tmpDir("azul-pack-test-");
  config.syncDir = tmp;
  const outputPath = path.join(tmp, "custom.sourcemap.json");

  fs.writeFileSync(
    outputPath,
    JSON.stringify({
      name: "Game",
      className: "DataModel",
      children: [
        {
          name: "Leftover",
          className: "Folder",
          guid: "stale-guid",
          children: [],
        },
      ],
    }),
    "utf8",
  );

  const pack = new PackCommand({ outputPath });
  try {
    assert.strictEqual((pack as any).outputPath, path.resolve(outputPath));

    const snapshot = [
      {
        guid: "groot",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
      },
    ];

    const { sourcemap } = (pack as any).buildSourcemap(snapshot);
    (pack as any).writeSourcemap(sourcemap, (pack as any).outputPath);

    const written = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.strictEqual(written.children.length, 1);
    assert.strictEqual(written.children[0].name, "ReplicatedStorage");
    assert.strictEqual(
      written.children.some((n: any) => n.guid === "stale-guid"),
      false,
    );
  } finally {
    (pack as any).ipc.close();
    config.syncDir = prevSyncDir;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
