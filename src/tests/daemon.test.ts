import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { SyncDaemon } from "../index.js";
import { config } from "../config.js";

function makeTempDir(prefix = "azul-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

/** Walk a generated sourcemap tree by exact DataModel path (from the root). */
function findInSourcemap(root: any, pathSegments: string[]): any {
  let current = root;
  for (const segment of pathSegments) {
    if (!current || !Array.isArray(current.children)) return undefined;
    current = current.children.find((c: any) => c.name === segment);
  }
  return current;
}

function readSourcemap(): any {
  return JSON.parse(fs.readFileSync(config.sourcemapPath, "utf8"));
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

test("fullSnapshot writes scripts, generates sourcemap, and removes orphans", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevDeleteOrphansOnConnect = config.deleteOrphansOnConnect;
  let daemon: SyncDaemon | undefined;
  try {
    // Configure daemon to use our temp dir and an ephemeral port
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.deleteOrphansOnConnect = true;

    // Create an orphan file that should be removed on snapshot
    const orphanDir = path.join(tmp, "extra");
    fs.mkdirSync(orphanDir, { recursive: true });
    const orphanPath = path.join(orphanDir, "orphan.luau");
    fs.writeFileSync(orphanPath, "print('i am orphan')", "utf8");
    assert.ok(fs.existsSync(orphanPath), "orphan created");

    daemon = new SyncDaemon();

    const instances = [
      {
        guid: "r1",
        className: "Folder",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
      },
      {
        guid: "m1",
        className: "Folder",
        name: "Modules",
        path: ["ReplicatedStorage", "Modules"],
      },
      {
        guid: "s1",
        className: "ModuleScript",
        name: "Foo",
        path: ["ReplicatedStorage", "Modules", "Foo"],
        source: "print('hello')",
      },
    ];

    // Send full snapshot
    (daemon as any).handleStudioMessage({
      type: "fullSnapshot",
      data: instances,
    });

    const expectedFile = path.join(
      tmp,
      "ReplicatedStorage",
      "Modules",
      "Foo.luau",
    );
    assert.ok(fs.existsSync(expectedFile), "script file was written");

    assert.ok(fs.existsSync(config.sourcemapPath), "sourcemap was generated");
    const sourcemap = JSON.parse(fs.readFileSync(config.sourcemapPath, "utf8"));
    assert.strictEqual(sourcemap.name, "Game");

    // Orphan file should have been removed
    assert.strictEqual(fs.existsSync(orphanPath), false, "orphan file removed");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.deleteOrphansOnConnect = prevDeleteOrphansOnConnect;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("scriptChanged creates file when node missing", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  let daemon: SyncDaemon | undefined;
  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;

    daemon = new SyncDaemon();

    const msg = {
      type: "scriptChanged",
      data: {
        guid: "new1",
        path: ["ReplicatedStorage", "Modules", "Bar"],
        className: "ModuleScript",
        source: "print('bar')",
      },
    } as any;

    (daemon as any).handleStudioMessage(msg);

    const expected = path.join(tmp, "ReplicatedStorage", "Modules", "Bar.luau");
    assert.ok(fs.existsSync(expected), "scriptChanged created file");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("deleted removes files and updates sourcemap", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  let daemon: SyncDaemon | undefined;
  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;

    daemon = new SyncDaemon();

    // Create snapshot with one script
    const instances = [
      {
        guid: "r1",
        className: "Folder",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
      },
      {
        guid: "m1",
        className: "Folder",
        name: "Modules",
        path: ["ReplicatedStorage", "Modules"],
      },
      {
        guid: "sdel",
        className: "ModuleScript",
        name: "ToDelete",
        path: ["ReplicatedStorage", "Modules", "ToDelete"],
        source: "print('bye')",
      },
    ];

    (daemon as any).handleStudioMessage({
      type: "fullSnapshot",
      data: instances,
    });
    const filePath = path.join(
      tmp,
      "ReplicatedStorage",
      "Modules",
      "ToDelete.luau",
    );
    assert.ok(fs.existsSync(filePath), "initial file exists");
    assert.ok(fs.existsSync(config.sourcemapPath), "sourcemap exists");

    // Send delete
    (daemon as any).handleStudioMessage({
      type: "deleted",
      data: { guid: "sdel" },
    });

    // File should be removed
    assert.strictEqual(fs.existsSync(filePath), false, "file was deleted");

    // Sourcemap should also be pruned for the deleted node/path
    const sourcemapRaw = fs.readFileSync(config.sourcemapPath, "utf8");
    const sourcemap = JSON.parse(sourcemapRaw);
    assert.notStrictEqual(sourcemapRaw.includes('"guid": "sdel"'), true);
    assert.notStrictEqual(sourcemapRaw.includes('"name": "ToDelete"'), true);
    const hasDeletedPath = (node: any, pathSegments: string[]): boolean => {
      if (!node || !Array.isArray(node.children)) return false;
      for (const child of node.children) {
        if (child.name === pathSegments[0]) {
          if (pathSegments.length === 1) return true;
          if (hasDeletedPath(child, pathSegments.slice(1))) return true;
        }
        if (hasDeletedPath(child, pathSegments)) return true;
      }
      return false;
    };
    assert.strictEqual(
      hasDeletedPath(sourcemap, ["ReplicatedStorage", "Modules", "ToDelete"]),
      false,
      "deleted path removed from sourcemap",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("filesystem live sync triggers createInstance and deleteInstance IPC messages", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();

    const sentMessages: any[] = [];
    (daemon as any).ipc.send = (msg: any) => {
      sentMessages.push(msg);
      return true;
    };

    // Test handleFileAdd for a Server script
    const serverScriptPath = path.join(
      tmp,
      "ReplicatedStorage",
      "Test.server.luau",
    );
    (daemon as any).handleFileAdd(serverScriptPath, "print('server')");

    assert.strictEqual(sentMessages.length, 1);
    assert.deepStrictEqual(sentMessages[0], {
      type: "createInstance",
      className: "Script",
      name: "Test",
      parentPath: ["ReplicatedStorage"],
      source: "print('server')",
    });

    sentMessages.length = 0;

    // Test handleDirAdd
    const dirPath = path.join(tmp, "ReplicatedStorage", "NewFolder");
    (daemon as any).handleDirAdd(dirPath);

    assert.strictEqual(sentMessages.length, 1);
    assert.deepStrictEqual(sentMessages[0], {
      type: "createInstance",
      className: "Folder",
      name: "NewFolder",
      parentPath: ["ReplicatedStorage"],
      source: undefined,
    });

    sentMessages.length = 0;

    // Test handleFileDelete for an unmapped file
    (daemon as any).handleFileDelete(serverScriptPath);

    assert.strictEqual(sentMessages.length, 1);
    assert.deepStrictEqual(sentMessages[0], {
      type: "deleteInstance",
      guid: undefined,
      path: ["ReplicatedStorage", "Test"],
    });

    sentMessages.length = 0;

    // Test handleDirDelete
    (daemon as any).handleDirDelete(dirPath);

    assert.strictEqual(sentMessages.length, 1);
    assert.deepStrictEqual(sentMessages[0], {
      type: "deleteInstance",
      guid: undefined,
      path: ["ReplicatedStorage", "NewFolder"],
    });
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("renaming a folder on disk moves the instance and preserves non-script descendants", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();

    // Studio has: ReplicatedStorage > Parent(Folder) > { Thing(Part), S(Script) }
    const tree = (daemon as any).tree;
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "gP",
        className: "Folder",
        name: "Parent",
        path: ["ReplicatedStorage", "Parent"],
        parentGuid: "rs",
      },
      {
        guid: "gPart",
        className: "Part",
        name: "Thing",
        path: ["ReplicatedStorage", "Parent", "Thing"],
        parentGuid: "gP",
      },
      {
        guid: "gS",
        className: "Script",
        name: "S",
        path: ["ReplicatedStorage", "Parent", "S"],
        parentGuid: "gP",
        source: "print(1)",
      },
    ]);

    // Write scripts to disk (creates Parent/ and maps the script), then record
    // folder inodes as the daemon does after a snapshot.
    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();

    const sentMessages: any[] = [];
    (daemon as any).ipc.send = (msg: any) => {
      sentMessages.push(msg);
      return true;
    };

    // Real rename preserves the directory inode.
    const parentDir = path.join(tmp, "ReplicatedStorage", "Parent");
    const renamedDir = path.join(tmp, "ReplicatedStorage", "Renamed");
    const oldScript = path.join(parentDir, "S.server.luau");
    fs.renameSync(parentDir, renamedDir);

    // Real ordering: the script's unlink (carrying its OLD path) is processed
    // first and tears the script node out of the tree, then the folder's
    // unlinkDir, then the folder's addDir. This desync is what broke content
    // matching; inode matching is immune to it.
    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleDirDelete(parentDir);
    (daemon as any).handleDirAdd(renamedDir);

    const moves = sentMessages.filter((m) => m.type === "moveInstance");
    assert.deepStrictEqual(moves, [
      {
        type: "moveInstance",
        guid: "gP",
        parentPath: ["ReplicatedStorage"],
        name: "Renamed",
        className: undefined,
        source: undefined,
      },
    ]);

    // The folder itself is never deleted (that would destroy the Part in Studio).
    const folderDeletes = sentMessages.filter(
      (m) => m.type === "deleteInstance" && m.guid === "gP",
    );
    assert.strictEqual(folderDeletes.length, 0, "folder is moved, not deleted");

    // The non-script Part survives and rode along to the new path.
    const part = tree.getNode("gPart");
    assert.ok(part, "Part node still exists");
    assert.deepStrictEqual(part.path, [
      "ReplicatedStorage",
      "Renamed",
      "Thing",
    ]);

    // The descendant script's own mapping is fixed proactively — not left
    // stale until a later round-trip self-heals it.
    const scriptMapping = (daemon as any).fileWriter.getMapping("gS");
    const newScriptPath = path.join(renamedDir, "S.server.luau");
    assert.strictEqual(
      path.resolve(scriptMapping.filePath),
      path.resolve(newScriptPath),
      "descendant script mapping points at its new path immediately",
    );

    // The physical file the folder rename already relocated is now recognized
    // as already-mapped when its own "add" event eventually arrives — not
    // treated as an unrelated new file.
    sentMessages.length = 0;
    (daemon as any).handleFileAdd(
      newScriptPath,
      fs.readFileSync(newScriptPath, "utf8"),
    );
    assert.strictEqual(
      sentMessages.filter((m) => m.type === "createInstance").length,
      0,
      "descendant script's add event does not spawn a spurious createInstance",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("moving a script file on disk moves the instance and preserves non-script descendants", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();

    // ReplicatedStorage > Module(ModuleScript) > Thing(Part, non-script descendant).
    const tree = (daemon as any).tree;
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "ws",
        className: "Workspace",
        name: "Workspace",
        path: ["Workspace"],
        parentGuid: "root",
      },
      {
        guid: "gM",
        className: "ModuleScript",
        name: "Module",
        path: ["ReplicatedStorage", "Module"],
        parentGuid: "rs",
        source: "return {}",
      },
      {
        guid: "gPart",
        className: "Part",
        name: "Thing",
        path: ["ReplicatedStorage", "Module", "Thing"],
        parentGuid: "gM",
      },
    ]);

    // Write the script to disk (creates ReplicatedStorage/Module.luau and maps
    // it), then record inodes as the daemon does after a snapshot.
    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();

    const sentMessages: any[] = [];
    (daemon as any).ipc.send = (msg: any) => {
      sentMessages.push(msg);
      return true;
    };

    // Real move preserves the file's inode (mirrors the reported bug: moving
    // Module.luau from ReplicatedStorage to Workspace).
    const oldScript = path.join(tmp, "ReplicatedStorage", "Module.luau");
    const newScript = path.join(tmp, "Workspace", "Module.luau");
    fs.mkdirSync(path.dirname(newScript), { recursive: true });
    fs.renameSync(oldScript, newScript);

    // Real chokidar ordering: unlink (old path) fires before add (new path).
    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(
      newScript,
      fs.readFileSync(newScript, "utf8"),
    );

    const moves = sentMessages.filter((m) => m.type === "moveInstance");
    assert.deepStrictEqual(moves, [
      {
        type: "moveInstance",
        guid: "gM",
        parentPath: ["Workspace"],
        name: "Module",
        className: undefined,
        source: undefined,
      },
    ]);

    // The script itself is never deleted (that would destroy the Part in Studio).
    const scriptDeletes = sentMessages.filter(
      (m) => m.type === "deleteInstance" && m.guid === "gM",
    );
    assert.strictEqual(scriptDeletes.length, 0, "script is moved, not deleted");

    // The non-script Part survives and rode along to the new path.
    const part = tree.getNode("gPart");
    assert.ok(part, "Part node still exists");
    assert.deepStrictEqual(part.path, ["Workspace", "Module", "Thing"]);
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("renaming a script's suffix propagates the class change (ModuleScript -> Script)", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    tree.applyFullSnapshot([
      { guid: "rs", className: "ReplicatedStorage", name: "ReplicatedStorage", path: ["ReplicatedStorage"], parentGuid: "root" },
      { guid: "gM", className: "ModuleScript", name: "Foo", path: ["ReplicatedStorage", "Foo"], parentGuid: "rs", source: "return {}" },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();

    const sentMessages: any[] = [];
    (daemon as any).ipc.send = (msg: any) => {
      sentMessages.push(msg);
      return true;
    };

    // Foo.luau -> Foo.server.luau: same name and directory, only the suffix
    // (and therefore the implied class) changes.
    const oldScript = path.join(tmp, "ReplicatedStorage", "Foo.luau");
    const newScript = path.join(tmp, "ReplicatedStorage", "Foo.server.luau");
    fs.renameSync(oldScript, newScript);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(newScript, fs.readFileSync(newScript, "utf8"));

    const moves = sentMessages.filter((m) => m.type === "moveInstance");
    assert.strictEqual(moves.length, 1);
    assert.strictEqual(moves[0].className, "Script", "class change is sent to Studio");

    const node = tree.getNode("gM");
    assert.strictEqual(node.className, "Script", "daemon tree reflects the new class");

    // FileWriter's mapping matches the actual renamed file, not the old path.
    const mapping = (daemon as any).fileWriter.getMapping("gM");
    assert.strictEqual(
      path.resolve(mapping.filePath),
      path.resolve(newScript),
      "file mapping points at the renamed file",
    );

    // The dangling buffered-delete timer must not fire and destroy the
    // instance after the fact.
    await wait(650);
    const deletes = sentMessages.filter(
      (m) => m.type === "deleteInstance" && m.guid === "gM",
    );
    assert.strictEqual(deletes.length, 0, "no delayed delete for the renamed instance");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("renaming a script's suffix propagates the class change (Script -> ModuleScript)", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    tree.applyFullSnapshot([
      { guid: "rs", className: "ReplicatedStorage", name: "ReplicatedStorage", path: ["ReplicatedStorage"], parentGuid: "root" },
      { guid: "gS", className: "Script", name: "Foo", path: ["ReplicatedStorage", "Foo"], parentGuid: "rs", source: "print(1)" },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();

    const sentMessages: any[] = [];
    (daemon as any).ipc.send = (msg: any) => {
      sentMessages.push(msg);
      return true;
    };

    // Foo.server.luau -> Foo.luau: dropping the suffix implies ModuleScript.
    const oldScript = path.join(tmp, "ReplicatedStorage", "Foo.server.luau");
    const newScript = path.join(tmp, "ReplicatedStorage", "Foo.luau");
    fs.renameSync(oldScript, newScript);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(newScript, fs.readFileSync(newScript, "utf8"));

    const moves = sentMessages.filter((m) => m.type === "moveInstance");
    assert.strictEqual(moves.length, 1);
    assert.strictEqual(moves[0].className, "ModuleScript", "class change is sent to Studio");

    const node = tree.getNode("gS");
    assert.strictEqual(node.className, "ModuleScript", "daemon tree reflects the new class");

    await wait(650);
    const deletes = sentMessages.filter(
      (m) => m.type === "deleteInstance" && m.guid === "gS",
    );
    assert.strictEqual(deletes.length, 0, "no delayed delete for the renamed instance");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("moving a script file relocates its nested-scripts children folder alongside it", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();

    // ReplicatedStorage > Module(ModuleScript) > Script1(Script, nested script descendant).
    const tree = (daemon as any).tree;
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "ws",
        className: "Workspace",
        name: "Workspace",
        path: ["Workspace"],
        parentGuid: "root",
      },
      {
        guid: "gM",
        className: "ModuleScript",
        name: "Module",
        path: ["ReplicatedStorage", "Module"],
        parentGuid: "rs",
        source: "return {}",
      },
      {
        guid: "gS1",
        className: "Script",
        name: "Script1",
        path: ["ReplicatedStorage", "Module", "Script1"],
        parentGuid: "gM",
        source: "print(1)",
      },
    ]);

    // Write the tree to disk: creates ReplicatedStorage/Module.luau AND the
    // nested-scripts container ReplicatedStorage/Module/Script1.server.luau.
    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();

    const oldFolder = path.join(tmp, "ReplicatedStorage", "Module");
    const oldNestedScript = path.join(oldFolder, "Script1.server.luau");
    assert.ok(
      fs.existsSync(oldNestedScript),
      "sanity: nested script written under Module/",
    );

    (daemon as any).ipc.send = () => true;

    // Only the script FILE is moved (mirrors the reported bug exactly): the
    // OS operation doesn't know to also move the sibling Module/ folder.
    const oldScript = path.join(tmp, "ReplicatedStorage", "Module.luau");
    const newScript = path.join(tmp, "Workspace", "Module.luau");
    fs.mkdirSync(path.dirname(newScript), { recursive: true });
    fs.renameSync(oldScript, newScript);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(
      newScript,
      fs.readFileSync(newScript, "utf8"),
    );

    const newFolder = path.join(tmp, "Workspace", "Module");
    const newNestedScript = path.join(newFolder, "Script1.server.luau");

    assert.ok(
      !fs.existsSync(oldFolder),
      "old children folder no longer exists",
    );
    assert.ok(
      fs.existsSync(newNestedScript),
      "children folder relocated alongside the script",
    );

    // FileWriter's mapping for the nested script is updated, not left stale.
    const mapping = (daemon as any).fileWriter.getMapping("gS1");
    assert.strictEqual(
      path.resolve(mapping.filePath),
      path.resolve(newNestedScript),
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("moving a folder to a different parent updates the tree's parent/child linkage, not just its path", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;

    daemon = new SyncDaemon();

    // ReplicatedStorage > Foo(Folder) > Thing(Part); ServerStorage is the move destination.
    const tree = (daemon as any).tree;
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "ss",
        className: "ServerStorage",
        name: "ServerStorage",
        path: ["ServerStorage"],
        parentGuid: "root",
      },
      {
        guid: "gF",
        className: "Folder",
        name: "Foo",
        path: ["ReplicatedStorage", "Foo"],
        parentGuid: "rs",
      },
      {
        guid: "gPart",
        className: "Part",
        name: "Thing",
        path: ["ReplicatedStorage", "Foo", "Thing"],
        parentGuid: "gF",
      },
    ]);

    (daemon as any).ipc.send = () => true;

    // Move Foo from ReplicatedStorage to ServerStorage.
    (daemon as any).performInstanceMove(
      "gF",
      ["ReplicatedStorage", "Foo"],
      ["ServerStorage", "Foo"],
    );

    const rs = tree.getNode("rs");
    const ss = tree.getNode("ss");
    const folder = tree.getNode("gF");

    assert.deepStrictEqual(
      folder.path,
      ["ServerStorage", "Foo"],
      "path updated",
    );
    assert.strictEqual(
      folder.parent?.guid,
      "ss",
      "parent link points at the new parent",
    );
    assert.ok(
      !rs.children.has("gF"),
      "old parent no longer lists the folder as a child",
    );
    assert.ok(ss.children.has("gF"), "new parent lists the folder as a child");

    // A later delete of the OLD parent must not cascade into the moved subtree.
    tree.deleteInstance("rs");
    assert.ok(
      tree.getNode("gF"),
      "moved folder survives deletion of its old parent",
    );
    assert.ok(tree.getNode("gPart"), "moved folder's descendant survives too");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("moving a script to become nested under another script resolves the correct parent", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;

    daemon = new SyncDaemon();

    // ReplicatedStorage > { Module(ModuleScript) > Sub(Script), Other(ModuleScript) }.
    // destinationParent must resolve Other even though it's a script, not a folder.
    const tree = (daemon as any).tree;
    tree.applyFullSnapshot([
      { guid: "rs", className: "ReplicatedStorage", name: "ReplicatedStorage", path: ["ReplicatedStorage"], parentGuid: "root" },
      { guid: "gM", className: "ModuleScript", name: "Module", path: ["ReplicatedStorage", "Module"], parentGuid: "rs", source: "return {}" },
      { guid: "gSub", className: "Script", name: "Sub", path: ["ReplicatedStorage", "Module", "Sub"], parentGuid: "gM", source: "print(1)" },
      { guid: "gOther", className: "ModuleScript", name: "Other", path: ["ReplicatedStorage", "Other"], parentGuid: "rs", source: "return {}" },
    ]);

    (daemon as any).ipc.send = () => true;

    // Move Sub from under Module to under Other (a script, not a folder).
    (daemon as any).performInstanceMove(
      "gSub",
      ["ReplicatedStorage", "Module", "Sub"],
      ["ReplicatedStorage", "Other", "Sub"],
    );

    const module_ = tree.getNode("gM");
    const other = tree.getNode("gOther");
    const sub = tree.getNode("gSub");

    assert.deepStrictEqual(sub.path, ["ReplicatedStorage", "Other", "Sub"]);
    assert.strictEqual(
      sub.parent?.guid,
      "gOther",
      "parent link points at the script-class destination parent",
    );
    assert.ok(
      !module_.children.has("gSub"),
      "old script parent no longer lists Sub as a child",
    );
    assert.ok(
      other.children.has("gSub"),
      "new script parent lists Sub as a child",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("empty folder instances are preserved by cleanupDirectories", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;

    daemon = new SyncDaemon();

    // Create an empty folder on disk
    const emptyFolderPath = path.join(tmp, "ReplicatedStorage", "MyFolder");
    fs.mkdirSync(emptyFolderPath, { recursive: true });

    // Snapshot contains an empty Folder instance at ReplicatedStorage/MyFolder
    const instances = [
      {
        guid: "r1",
        className: "Folder",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
      },
      {
        guid: "f1",
        className: "Folder",
        name: "MyFolder",
        path: ["ReplicatedStorage", "MyFolder"],
      },
    ];

    (daemon as any).handleStudioMessage({
      type: "fullSnapshot",
      data: instances,
    });

    // Verify the empty directory was NOT cleaned up
    assert.ok(
      fs.existsSync(emptyFolderPath),
      "empty Folder instance directory was preserved",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// --- Sourcemap staleness after external (filesystem) actions ---

test("sourcemap has no stale entries after a folder is renamed on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    // ReplicatedStorage > Parent(Folder) > S(Script)
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "gP",
        className: "Folder",
        name: "Parent",
        path: ["ReplicatedStorage", "Parent"],
        parentGuid: "rs",
      },
      {
        guid: "gS",
        className: "Script",
        name: "S",
        path: ["ReplicatedStorage", "Parent", "S"],
        parentGuid: "gP",
        source: "print(1)",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    const before = readSourcemap();
    assert.ok(
      findInSourcemap(before, ["ReplicatedStorage", "Parent"]),
      "sanity: initial sourcemap has the folder at its original path",
    );

    // Real rename preserves the directory inode.
    const parentDir = path.join(tmp, "ReplicatedStorage", "Parent");
    const renamedDir = path.join(tmp, "ReplicatedStorage", "Renamed");
    const oldScript = path.join(parentDir, "S.server.luau");
    fs.renameSync(parentDir, renamedDir);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleDirDelete(parentDir);
    (daemon as any).handleDirAdd(renamedDir);

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Parent"]),
      undefined,
      "no stale entry left at the old folder path",
    );

    const folderNode = findInSourcemap(after, ["ReplicatedStorage", "Renamed"]);
    assert.ok(folderNode, "folder entry exists at the new path");
    assert.strictEqual(folderNode.guid, "gP");

    const scriptNode = findInSourcemap(after, [
      "ReplicatedStorage",
      "Renamed",
      "S",
    ]);
    assert.ok(scriptNode, "descendant script entry exists at the new path");
    const newScriptPath = path.join(renamedDir, "S.server.luau");
    assert.strictEqual(
      path.resolve(process.cwd(), scriptNode.filePaths[0]),
      path.resolve(newScriptPath),
      "descendant script's filePaths point at its new location, not the old one",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("sourcemap has no stale entries after a folder is moved to a different parent on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    // ReplicatedStorage > Foo(Folder) > S(Script); ServerStorage is the destination.
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "ss",
        className: "ServerStorage",
        name: "ServerStorage",
        path: ["ServerStorage"],
        parentGuid: "root",
      },
      {
        guid: "gF",
        className: "Folder",
        name: "Foo",
        path: ["ReplicatedStorage", "Foo"],
        parentGuid: "rs",
      },
      {
        guid: "gS",
        className: "Script",
        name: "S",
        path: ["ReplicatedStorage", "Foo", "S"],
        parentGuid: "gF",
        source: "print(1)",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    assert.ok(
      findInSourcemap(readSourcemap(), ["ReplicatedStorage", "Foo"]),
      "sanity: initial sourcemap has the folder under ReplicatedStorage",
    );

    const oldDir = path.join(tmp, "ReplicatedStorage", "Foo");
    const newDir = path.join(tmp, "ServerStorage", "Foo");
    const oldScript = path.join(oldDir, "S.server.luau");
    fs.mkdirSync(path.dirname(newDir), { recursive: true });
    fs.renameSync(oldDir, newDir);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleDirDelete(oldDir);
    (daemon as any).handleDirAdd(newDir);

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Foo"]),
      undefined,
      "no stale entry left under the old parent",
    );

    const folderNode = findInSourcemap(after, ["ServerStorage", "Foo"]);
    assert.ok(folderNode, "folder entry exists under the new parent");
    assert.strictEqual(folderNode.guid, "gF");

    const scriptNode = findInSourcemap(after, ["ServerStorage", "Foo", "S"]);
    assert.ok(
      scriptNode,
      "descendant script entry exists under the new parent",
    );
    const newScriptPath = path.join(newDir, "S.server.luau");
    assert.strictEqual(
      path.resolve(process.cwd(), scriptNode.filePaths[0]),
      path.resolve(newScriptPath),
      "descendant script's filePaths point at its new location",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("sourcemap prunes the entry when a folder is deleted on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "gP",
        className: "Folder",
        name: "Parent",
        path: ["ReplicatedStorage", "Parent"],
        parentGuid: "rs",
      },
      {
        guid: "gS",
        className: "Script",
        name: "S",
        path: ["ReplicatedStorage", "Parent", "S"],
        parentGuid: "gP",
        source: "print(1)",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    assert.ok(
      findInSourcemap(readSourcemap(), ["ReplicatedStorage", "Parent"]),
      "sanity: initial sourcemap has the folder",
    );

    const parentDir = path.join(tmp, "ReplicatedStorage", "Parent");
    const script = path.join(parentDir, "S.server.luau");
    fs.rmSync(parentDir, { recursive: true, force: true });

    // Real ordering: the descendant script's unlink fires before the folder's.
    (daemon as any).handleFileDelete(script);
    (daemon as any).handleDirDelete(parentDir);

    // No matching add arrives — let the buffered deletes flush for real.
    await wait(650);

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Parent"]),
      undefined,
      "folder entry pruned",
    );
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Parent", "S"]),
      undefined,
      "descendant script entry pruned too",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("sourcemap has no stale entry after a script is renamed on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "gM",
        className: "ModuleScript",
        name: "Module",
        path: ["ReplicatedStorage", "Module"],
        parentGuid: "rs",
        source: "return {}",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    assert.ok(
      findInSourcemap(readSourcemap(), ["ReplicatedStorage", "Module"]),
      "sanity: initial sourcemap has the script",
    );

    const oldScript = path.join(tmp, "ReplicatedStorage", "Module.luau");
    const newScript = path.join(tmp, "ReplicatedStorage", "IGotRenamed.luau");
    fs.renameSync(oldScript, newScript);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(
      newScript,
      fs.readFileSync(newScript, "utf8"),
    );

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Module"]),
      undefined,
      "no stale entry left at the old name",
    );

    const node = findInSourcemap(after, ["ReplicatedStorage", "IGotRenamed"]);
    assert.ok(node, "entry exists at the new name");
    assert.strictEqual(node.guid, "gM");
    assert.strictEqual(
      path.resolve(process.cwd(), node.filePaths[0]),
      path.resolve(newScript),
      "filePaths point at the renamed file",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("sourcemap has no stale entries after a script (with a nested descendant) is moved on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    // ReplicatedStorage > Module(ModuleScript) > Script1(Script, nested).
    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "ws",
        className: "Workspace",
        name: "Workspace",
        path: ["Workspace"],
        parentGuid: "root",
      },
      {
        guid: "gM",
        className: "ModuleScript",
        name: "Module",
        path: ["ReplicatedStorage", "Module"],
        parentGuid: "rs",
        source: "return {}",
      },
      {
        guid: "gS1",
        className: "Script",
        name: "Script1",
        path: ["ReplicatedStorage", "Module", "Script1"],
        parentGuid: "gM",
        source: "print(1)",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    const before = readSourcemap();
    assert.ok(findInSourcemap(before, ["ReplicatedStorage", "Module"]));
    assert.ok(
      findInSourcemap(before, ["ReplicatedStorage", "Module", "Script1"]),
    );

    // Only the script FILE is moved (the sibling children folder is not
    // touched by the OS operation itself — Azul has to relocate it).
    const oldScript = path.join(tmp, "ReplicatedStorage", "Module.luau");
    const newScript = path.join(tmp, "Workspace", "Module.luau");
    fs.mkdirSync(path.dirname(newScript), { recursive: true });
    fs.renameSync(oldScript, newScript);

    (daemon as any).handleFileDelete(oldScript);
    (daemon as any).handleFileAdd(
      newScript,
      fs.readFileSync(newScript, "utf8"),
    );

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Module"]),
      undefined,
      "no stale entry left at the old location",
    );

    const moduleNode = findInSourcemap(after, ["Workspace", "Module"]);
    assert.ok(moduleNode, "script entry exists at the new location");
    assert.strictEqual(moduleNode.guid, "gM");
    assert.strictEqual(
      path.resolve(process.cwd(), moduleNode.filePaths[0]),
      path.resolve(newScript),
    );

    const nestedNode = findInSourcemap(after, [
      "Workspace",
      "Module",
      "Script1",
    ]);
    assert.ok(
      nestedNode,
      "nested descendant entry exists under the new location",
    );
    assert.strictEqual(nestedNode.guid, "gS1");
    const newNestedPath = path.join(
      tmp,
      "Workspace",
      "Module",
      "Script1.server.luau",
    );
    assert.strictEqual(
      path.resolve(process.cwd(), nestedNode.filePaths[0]),
      path.resolve(newNestedPath),
      "nested descendant's filePaths point at its relocated file, not the old one",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("sourcemap prunes the entry when a script is deleted on disk", async () => {
  const tmp = makeTempDir();
  const prevSyncDir = config.syncDir;
  const prevSourcemapPath = config.sourcemapPath;
  const prevPort = config.port;
  const prevLiveFsSync = config.liveFsSync;
  let daemon: SyncDaemon | undefined;

  try {
    config.syncDir = tmp;
    config.sourcemapPath = path.join(tmp, "sourcemap.json");
    config.port = 0;
    config.liveFsSync = { ...prevLiveFsSync, enabled: true };

    daemon = new SyncDaemon();
    const tree = (daemon as any).tree;

    tree.applyFullSnapshot([
      {
        guid: "rs",
        className: "ReplicatedStorage",
        name: "ReplicatedStorage",
        path: ["ReplicatedStorage"],
        parentGuid: "root",
      },
      {
        guid: "gM",
        className: "ModuleScript",
        name: "Module",
        path: ["ReplicatedStorage", "Module"],
        parentGuid: "rs",
        source: "return {}",
      },
    ]);

    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordInodes();
    (daemon as any).regenerateSourcemap();
    (daemon as any).ipc.send = () => true;

    assert.ok(
      findInSourcemap(readSourcemap(), ["ReplicatedStorage", "Module"]),
      "sanity: initial sourcemap has the script",
    );

    const scriptPath = path.join(tmp, "ReplicatedStorage", "Module.luau");
    fs.rmSync(scriptPath);
    (daemon as any).handleFileDelete(scriptPath);

    // No matching add arrives — let the buffered delete flush for real.
    await wait(650);

    const after = readSourcemap();
    assert.strictEqual(
      findInSourcemap(after, ["ReplicatedStorage", "Module"]),
      undefined,
      "script entry pruned",
    );
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    config.liveFsSync = prevLiveFsSync;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
