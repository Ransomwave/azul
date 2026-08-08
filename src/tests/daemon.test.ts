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
    config.liveFsSync = true;

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
