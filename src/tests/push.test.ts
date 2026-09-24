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
  buildRojoInstances(
    destSegments: string[],
    sourceOverride?: string,
  ): Promise<InstanceData[] | null>;
  ipc: { close(): void };
};

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "azul-push-test-"));
}

/** `UI.client.luau` + `UI/Foo.luau` on disk, returns the temp root. */
function makePairedSource() {
  const tmp = makeTempDir();
  fs.mkdirSync(path.join(tmp, "UI"));
  fs.writeFileSync(
    path.join(tmp, "UI.client.luau"),
    'require("@self/Foo")',
    "utf8",
  );
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
  // `@self` must resolve against the destination name, not the sourcemap node.
  assert.strictEqual(root.source, 'require("./Menu/Foo")');
});

test("--dest rename rewrites @self against the destination name", async () => {
  const tmp = makePairedSource();
  const pair = push.resolveScriptPair(path.join(tmp, "UI.client.luau"), false);

  const instances = await push.buildPushInstancesFromFilesystem(
    pair.scriptFile,
    pair.childDir,
    ["PlayerGui", "Menu"],
  );

  const root = instances!.find((i) => i.path.length === 2)!;
  assert.strictEqual(root.name, "Menu");
  assert.strictEqual(root.source, 'require("./Menu/Foo")');
});

test.after(() => push.ipc.close());

test("rojo push without a project JSON imports loose JSON modules", async () => {
  const src = path.join(makeTempDir(), "src");
  fs.mkdirSync(src, { recursive: true });

  fs.writeFileSync(
    path.join(src, "Config.json"),
    JSON.stringify({ enabled: true, retries: 3 }),
    "utf8",
  );
  fs.writeFileSync(path.join(src, "Main.luau"), "return nil", "utf8");
  // A JSON file beside a same-named script is that script's data sibling, not a module
  fs.writeFileSync(path.join(src, "Main.json"), "{}", "utf8");
  // Meta and sourcemap files carry their own meaning and must not become modules
  fs.writeFileSync(path.join(src, "Main.meta.json"), "{}", "utf8");
  fs.writeFileSync(path.join(src, "sourcemap.json"), "{}", "utf8");
  // The loose walk applies the builder's default ignores, so VCS metadata stays out
  fs.mkdirSync(path.join(src, ".git"), { recursive: true });
  fs.writeFileSync(path.join(src, ".git", "Hook.luau"), "return 1", "utf8");

  const instances = await push.buildRojoInstances(["ReplicatedStorage"], src);
  assert.ok(instances);

  const byName = new Map(instances.map((i) => [i.name, i]));
  assert.equal(byName.has("Hook"), false, ".git contents must not be pushed");

  const config = byName.get("Config");
  assert.equal(config?.className, "ModuleScript");
  assert.match(config!.source!, /^return \{/);
  assert.match(config!.source!, /enabled = true/);
  assert.deepEqual(config!.path, ["ReplicatedStorage", "Config"]);

  // Main stays the script; the non-module JSON files are skipped
  assert.equal(byName.get("Main")?.source, "return nil");
  assert.equal(byName.has("Main.meta"), false);
  assert.equal(byName.has("sourcemap"), false);
});

test("rojo push dedupe collapses a Folder and a script on the same path", () => {
  const dedupe = (push as any).dedupeRojoInstances.bind(push) as (
    instances: InstanceData[],
  ) => InstanceData[];

  const at = (className: string, source?: string): InstanceData =>
    ({
      guid: className,
      className,
      name: "Shared",
      path: ["ReplicatedStorage", "Shared"],
      source,
    }) as InstanceData;

  // The script wins whichever order the two arrive in
  assert.deepEqual(
    dedupe([at("Folder"), at("ModuleScript", "return 1")]).map(
      (i) => i.className,
    ),
    ["ModuleScript"],
  );
  assert.deepEqual(
    dedupe([at("ModuleScript", "return 1"), at("Folder")]).map(
      (i) => i.className,
    ),
    ["ModuleScript"],
  );

  // Distinct paths are untouched
  assert.equal(
    dedupe([
      at("Folder"),
      { ...at("ModuleScript", "return 1"), path: ["ReplicatedStorage", "Other"] },
    ]).length,
    2,
  );
});

test("rojo push leaves project-owned directories to the project build", async () => {
  const tmp = makeTempDir();
  const pkgs = path.join(tmp, "pkgs");

  // A package carrying its own project file
  const withProj = path.join(pkgs, "withproj");
  fs.mkdirSync(path.join(withProj, "src"), { recursive: true });
  fs.writeFileSync(
    path.join(withProj, "src", "Mod.luau"),
    "return 'mod'",
    "utf8",
  );
  fs.writeFileSync(
    path.join(withProj, "default.project.json"),
    JSON.stringify({
      name: "Pkg",
      tree: { $className: "Folder", $path: "src" },
    }),
    "utf8",
  );

  // Loose content beside it, covered by no project
  fs.mkdirSync(path.join(pkgs, "loose"), { recursive: true });
  fs.writeFileSync(
    path.join(pkgs, "loose", "Helper.luau"),
    "return 'helper'",
    "utf8",
  );
  fs.writeFileSync(path.join(pkgs, "Stray.json"), '{"a":1}', "utf8");

  const instances = await push.buildRojoInstances(["ReplicatedStorage"], pkgs);
  assert.ok(instances);
  const paths = instances.map((i) => i.path.join("/"));

  // The project supplies its own subtree, flattened through its $path
  assert.ok(paths.includes("ReplicatedStorage/withproj/Mod"));
  // The loose walk supplies everything the project does not cover
  assert.ok(paths.includes("ReplicatedStorage/loose/Helper"));
  assert.ok(paths.includes("ReplicatedStorage/Stray"));

  // It must not descend into the project's own directory and re-emit its files
  assert.equal(
    paths.some((p) => p.includes("withproj/src")),
    false,
    "project-owned directory walked twice",
  );
  assert.equal(
    paths.some((p) => p.endsWith("withproj/default.project")),
    false,
    "project file emitted as a JSON module",
  );

  fs.rmSync(tmp, { recursive: true, force: true });
});
