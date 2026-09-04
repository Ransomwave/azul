import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { PushCommand } from "../push.js";
import type { InstanceData } from "../ipc/messages.js";

/**
 * The push helpers under test are internal; the command's WebSocket server is
 * irrelevant here, so one instance is shared and closed at the end.
 */
const push = new PushCommand({}) as unknown as {
  resolveScriptPair(
    sourcePath: string,
    isDirectory: boolean,
  ): { scriptFile: string | null; childDir: string | null; instanceName: string };
  buildPushInstancesFromFilesystem(
    scriptFile: string | null,
    childDir: string | null,
    containerPath: string[],
  ): Promise<InstanceData[] | null>;
  buildPushInstancesFromSourcemap(
    probePath: string,
    containerPath: string[],
    sourcemapPath: string,
    scriptFile: string | null,
  ): InstanceData[] | null;
  ipc: { close(): void };
};

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "azul-push-test-"));
}

/** `UI.client.luau` + `UI/Foo.luau` on disk, returns the temp root. */
function makePairedSource() {
  const tmp = makeTempDir();
  fs.mkdirSync(path.join(tmp, "UI"));
  fs.writeFileSync(path.join(tmp, "UI.client.luau"), "print('ui')", "utf8");
  fs.writeFileSync(path.join(tmp, "UI", "Foo.luau"), "return {}", "utf8");
  return tmp;
}

const summarize = (instances: InstanceData[]) =>
  instances.map((i) => `${i.path.join("/")}:${i.className}`).sort();

test("pushing a script file picks up its sibling children folder", async () => {
  const tmp = makePairedSource();
  const pair = push.resolveScriptPair(path.join(tmp, "UI.client.luau"), false);

  assert.strictEqual(pair.instanceName, "UI");
  assert.strictEqual(pair.childDir, path.join(tmp, "UI"));

  const instances = await push.buildPushInstancesFromFilesystem(
    pair.scriptFile,
    pair.childDir,
    ["StarterGui", "UI"],
  );

  assert.deepStrictEqual(summarize(instances!), [
    "StarterGui/UI/Foo:ModuleScript",
    "StarterGui/UI:LocalScript",
  ]);
});

test("pushing a children folder picks up its sibling script", async () => {
  const tmp = makePairedSource();
  const pair = push.resolveScriptPair(path.join(tmp, "UI"), true);

  assert.strictEqual(pair.scriptFile, path.join(tmp, "UI.client.luau"));

  const instances = await push.buildPushInstancesFromFilesystem(
    pair.scriptFile,
    pair.childDir,
    ["StarterGui", "UI"],
  );

  assert.deepStrictEqual(summarize(instances!), [
    "StarterGui/UI/Foo:ModuleScript",
    "StarterGui/UI:LocalScript",
  ]);
});

test("a folder with no sibling script still pushes as a plain folder tree", async () => {
  const tmp = makeTempDir();
  fs.mkdirSync(path.join(tmp, "Packages"));
  fs.writeFileSync(path.join(tmp, "Packages", "Signal.luau"), "return {}", "utf8");

  const pair = push.resolveScriptPair(path.join(tmp, "Packages"), true);
  assert.strictEqual(pair.scriptFile, null);

  const instances = await push.buildPushInstancesFromFilesystem(
    pair.scriptFile,
    pair.childDir,
    ["ReplicatedStorage", "Packages"],
  );

  assert.deepStrictEqual(summarize(instances!), [
    "ReplicatedStorage/Packages/Signal:ModuleScript",
  ]);
});

test("--from-sourcemap keeps the paired script as the subtree root", () => {
  const tmp = makePairedSource();
  const sourcemapPath = path.join(tmp, "sourcemap.json");
  const rel = (...segments: string[]) =>
    path.relative(process.cwd(), path.join(tmp, ...segments)).split(path.sep).join("/");

  fs.writeFileSync(
    sourcemapPath,
    JSON.stringify({
      name: "Game",
      className: "DataModel",
      children: [
        {
          name: "StarterGui",
          className: "StarterGui",
          children: [
            {
              name: "UI",
              className: "LocalScript",
              guid: "ui-guid",
              filePaths: [rel("UI.client.luau")],
              children: [
                {
                  name: "Foo",
                  className: "ModuleScript",
                  guid: "foo-guid",
                  filePaths: [rel("UI", "Foo.luau")],
                },
                { name: "Frame", className: "Frame", guid: "frame-guid" },
              ],
            },
          ],
        },
      ],
    }),
    "utf8",
  );

  const instances = push.buildPushInstancesFromSourcemap(
    path.join(tmp, "UI"),
    ["PlayerGui", "Menu"],
    sourcemapPath,
    path.join(tmp, "UI.client.luau"),
  );

  // Root is rebased and renamed to the destination; non-script descendants come along.
  assert.deepStrictEqual(summarize(instances!), [
    "PlayerGui/Menu/Foo:ModuleScript",
    "PlayerGui/Menu/Frame:Frame",
    "PlayerGui/Menu:LocalScript",
  ]);

  const root = instances!.find((i) => i.path.length === 2)!;
  assert.strictEqual(root.name, "Menu");
  assert.strictEqual(root.source, "print('ui')");
});

test.after(() => push.ipc.close());
