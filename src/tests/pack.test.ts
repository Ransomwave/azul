import test from "node:test";
import assert from "node:assert/strict";
import { PackCommand } from "../pack.js";
import { config } from "../config.js";

// Use ephemeral IPC port to avoid collisions
config.port = 0;

test("PackCommand regenerate and pack produce _azul metadata and pack nodes", () => {
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

    const root = (pack as any).regenerateSourcemap(snapshot, null);
    const packed = (pack as any).packIntoSourcemap(snapshot, root);
    assert.strictEqual(typeof root._azul?.packedAt, "string");
    assert.strictEqual(root._azul?.packVersion, 1);
    assert.strictEqual(typeof packed, "number");
  } finally {
    (pack as any).ipc.close();
  }
});
