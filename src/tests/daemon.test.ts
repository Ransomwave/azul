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
    const serverScriptPath = path.join(tmp, "ReplicatedStorage", "Test.server.luau");
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
      { guid: "rs", className: "ReplicatedStorage", name: "ReplicatedStorage", path: ["ReplicatedStorage"], parentGuid: "root" },
      { guid: "gP", className: "Folder", name: "Parent", path: ["ReplicatedStorage", "Parent"], parentGuid: "rs" },
      { guid: "gPart", className: "Part", name: "Thing", path: ["ReplicatedStorage", "Parent", "Thing"], parentGuid: "gP" },
      { guid: "gS", className: "Script", name: "S", path: ["ReplicatedStorage", "Parent", "S"], parentGuid: "gP", source: "print(1)" },
    ]);

    // Write scripts to disk (creates Parent/ and maps the script), then record
    // folder inodes as the daemon does after a snapshot.
    (daemon as any).fileWriter.writeTree(tree.getAllNodes());
    (daemon as any).recordFolderInodes();

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
      { type: "moveInstance", guid: "gP", parentPath: ["ReplicatedStorage"], name: "Renamed" },
    ]);

    // The folder itself is never deleted (that would destroy the Part in Studio).
    const folderDeletes = sentMessages.filter(
      (m) => m.type === "deleteInstance" && m.guid === "gP",
    );
    assert.strictEqual(folderDeletes.length, 0, "folder is moved, not deleted");

    // The non-script Part survives and rode along to the new path.
    const part = tree.getNode("gPart");
    assert.ok(part, "Part node still exists");
    assert.deepStrictEqual(part.path, ["ReplicatedStorage", "Renamed", "Thing"]);
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
      { guid: "rs", className: "ReplicatedStorage", name: "ReplicatedStorage", path: ["ReplicatedStorage"], parentGuid: "root" },
      { guid: "ss", className: "ServerStorage", name: "ServerStorage", path: ["ServerStorage"], parentGuid: "root" },
      { guid: "gF", className: "Folder", name: "Foo", path: ["ReplicatedStorage", "Foo"], parentGuid: "rs" },
      { guid: "gPart", className: "Part", name: "Thing", path: ["ReplicatedStorage", "Foo", "Thing"], parentGuid: "gF" },
    ]);

    (daemon as any).ipc.send = () => true;

    // Move Foo from ReplicatedStorage to ServerStorage.
    (daemon as any).performFolderMove(
      "gF",
      ["ReplicatedStorage", "Foo"],
      ["ServerStorage", "Foo"],
    );

    const rs = tree.getNode("rs");
    const ss = tree.getNode("ss");
    const folder = tree.getNode("gF");

    assert.deepStrictEqual(folder.path, ["ServerStorage", "Foo"], "path updated");
    assert.strictEqual(folder.parent?.guid, "ss", "parent link points at the new parent");
    assert.ok(!rs.children.has("gF"), "old parent no longer lists the folder as a child");
    assert.ok(ss.children.has("gF"), "new parent lists the folder as a child");

    // A later delete of the OLD parent must not cascade into the moved subtree.
    tree.deleteInstance("rs");
    assert.ok(tree.getNode("gF"), "moved folder survives deletion of its old parent");
    assert.ok(tree.getNode("gPart"), "moved folder's descendant survives too");
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
    assert.ok(fs.existsSync(emptyFolderPath), "empty Folder instance directory was preserved");
  } finally {
    await daemon?.stop();
    config.syncDir = prevSyncDir;
    config.sourcemapPath = prevSourcemapPath;
    config.port = prevPort;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
