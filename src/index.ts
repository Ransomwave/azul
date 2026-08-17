import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import * as http from "http";
import { IPCServer } from "./ipc/server.js";
import { TreeManager, TreeNode } from "./fs/treeManager.js";
import { FileWriter } from "./fs/fileWriter.js";
import { FileWatcher } from "./fs/watcher.js";
import { SourcemapGenerator } from "./sourcemap/generator.js";
import {
  classifyScriptFileName,
  isInitScriptFileName,
  isScriptFileName,
  normalizeLuaLikeFileName,
} from "./util/scriptFile.js";
import { log } from "./util/log.js";
import { config, initializeConfig } from "./config.js";
import type { StudioMessage } from "./ipc/messages.js";

/**
 * Main orchestrator for the Azul daemon
 */
export class SyncDaemon {
  private ipc: IPCServer;
  private httpServer: http.Server;
  private tree: TreeManager;
  private fileWriter: FileWriter;
  private fileWatcher: FileWatcher;
  private sourcemapGenerator: SourcemapGenerator;
  private batchDepth = 0; // Tracks nested batch processing
  private batchNeedsSourcemapRegen = false; // Defer regen until batch ends
  private stopPromise: Promise<void> | null = null;

  // Buffers a deletion briefly so a matching filesystem creation can become a
  // move instead of a destroy+recreate (Roblox's Destroy() cascades, so a
  // recreate would permanently lose non-script descendants like Parts).
  // Keyed by inode: stable across rename/move, immune to event-ordering races.
  // Falls back to a guid key when the inode is unknown.
  private pendingInstanceDeletes = new Map<
    string,
    { guid: string; oldSegments: string[]; timer: NodeJS.Timeout }
  >();
  private guidToInode = new Map<string, string>();
  private readonly moveWindowMs = Math.max(500, config.fileWatchDebounce * 5);

  constructor() {
    this.tree = new TreeManager();
    this.fileWriter = new FileWriter(config.syncDir);
    this.fileWatcher = new FileWatcher();
    this.sourcemapGenerator = new SourcemapGenerator();

    // Suppress watcher echoes for filesystem mutations the daemon performs
    // itself, so its own writes/deletes aren't mistaken for user actions.
    this.fileWriter.setEventSuppressor((filePath, event) => {
      this.fileWatcher.suppressNextEvent(filePath, event);
    });

    // HTTP server is used for WebSocket upgrade handling.
    this.httpServer = http.createServer((_, res) => {
      res.writeHead(404);
      res.end("Not found");
    });

    this.ipc = new IPCServer(config.port, this.httpServer, {
      requestSnapshotOnConnect: false,
    });

    this.setupHandlers();
    this.httpServer.listen(config.port);
  }

  /**
   * Set up all event handlers
   */
  private setupHandlers(): void {
    // Handle messages from Studio (WebSocket)
    this.ipc.onMessage((message) => this.handleStudioMessage(message));
    this.ipc.onHandshake(() => {
      this.ipc.requestSnapshot();
    });

    // Handle file & directory events from filesystem
    this.fileWatcher.onEvent((event, filePath, source) => {
      switch (event) {
        case "change":
          this.handleFileChange(filePath, source ?? "");
          break;
        case "add":
          this.handleFileAdd(filePath, source ?? "");
          break;
        case "unlink":
          this.handleFileDelete(filePath);
          break;
        case "addDir":
          this.handleDirAdd(filePath);
          break;
        case "unlinkDir":
          this.handleDirDelete(filePath);
          break;
      }
    });
  }

  /**
   * Handle incoming messages from Studio
   */
  private handleStudioMessage(message: StudioMessage): void {
    if (message.type === "batch") {
      this.batchDepth += 1;
      try {
        for (const payload of message.messages) {
          this.handleStudioMessage(payload);
        }
      } finally {
        this.batchDepth -= 1;

        // If any delete in this batch missed its prune, only regenerate once at the end
        if (this.batchDepth === 0 && this.batchNeedsSourcemapRegen) {
          this.regenerateSourcemap();
          this.batchNeedsSourcemapRegen = false;
        }
      }
      return;
    }

    switch (message.type) {
      case "fullSnapshot":
        this.handleFullSnapshot(message.data);
        break;

      case "scriptChanged":
        this.handleScriptChanged(message.data);
        break;

      case "instanceUpdated":
        this.handleInstanceUpdated(message.data);
        break;

      case "deleted":
        this.handleDeleted(message.data);
        break;

      case "ping":
        this.ipc.send({ type: "pong" });
        break;

      case "clientDisconnect":
        log.info("Studio requested daemon shutdown");
        void (async () => {
          await this.stop();
          process.exit(0);
        })();
        break;

      default:
        log.warn("Unknown message type:", (message as any).type);
    }
  }

  /**
   * Handle full snapshot from Studio
   */
  private handleFullSnapshot(data: any[]): void {
    log.info("Received full snapshot from Studio");

    // Update tree
    this.tree.applyFullSnapshot(data);

    // Write all scripts to filesystem
    this.fileWriter.writeTree(this.tree.getAllNodes());

    // Record inodes so a later filesystem rename/move can be recognized as a
    // move (preserving non-script descendants) rather than a destroy + rebuild.
    this.recordInodes();

    // Remove any pre-existing files that are no longer mapped (optional)
    this.cleanupOrphanFiles();

    // Start file watching
    this.fileWatcher.watch(this.fileWriter.getBaseDir());

    // Generate sourcemap
    this.regenerateSourcemap();

    // Log statistics
    const stats = this.tree.getStats();
    log.success(
      `Sync complete: ${stats.scriptNodes} scripts, ${stats.totalNodes} total nodes`,
    );
  }

  /**
   * Handle script source change
   */
  private handleScriptChanged(message: {
    guid: string;
    source: string;
    path: string[];
    className: string;
  }): void {
    const { guid, source, path: instancePath, className } = message;

    // Update tree
    this.tree.updateScriptSource(guid, source);

    // Get or create node
    let node = this.tree.getNode(guid);
    if (!node) {
      // Create new node if it doesn't exist
      this.tree.updateInstance({
        guid,
        className,
        name: instancePath[instancePath.length - 1],
        path: instancePath,
        source,
      });
      node = this.tree.getNode(guid);
    }

    if (node) {
      // Precompute path and suppress watcher before writing to avoid race conditions
      const filePath = this.fileWriter.getFilePath(node);
      this.fileWatcher.suppressNextChange(filePath, source);

      // Write to filesystem
      this.fileWriter.writeScript(node);

      // Incrementally update sourcemap entry for this script
      this.sourcemapGenerator.upsertSubtree(
        node,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings(),
        config.sourcemapPath,
        undefined,
        false,
      );
    }
  }

  /**
   * Handle instance update (rename, move, etc.)
   */
  private handleInstanceUpdated(data: any): void {
    const update = this.tree.updateInstance(data);
    const node = update?.node;

    if (!node) {
      return;
    }

    const scriptsToUpdate: Map<string, TreeNode> = new Map();

    if (this.isScriptClass(node.className)) {
      scriptsToUpdate.set(node.guid, node);
    }

    if (update.pathChanged || update.nameChanged || update.parentChanged) {
      for (const child of this.tree.getDescendantScripts(node.guid)) {
        scriptsToUpdate.set(child.guid, child);
      }
    }

    for (const scriptNode of scriptsToUpdate.values()) {
      const filePath = this.fileWriter.getFilePath(scriptNode);
      this.fileWatcher.suppressNextChange(filePath, scriptNode.source);
      this.fileWriter.writeScript(scriptNode);
    }

    const shouldUpdateSourcemap =
      update.isNew ||
      update.pathChanged ||
      update.nameChanged ||
      update.parentChanged ||
      this.isScriptClass(node.className);

    if (shouldUpdateSourcemap) {
      this.sourcemapGenerator.upsertSubtree(
        node,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings(),
        config.sourcemapPath,
        update.prevPath,
        update.isNew,
      );
    }

    // Keep inode tracking current for newly created/moved instances so a later
    // filesystem rename/move can be recognized as a move rather than a
    // destroy + rebuild.
    this.recordInode(node);

    this.cleanupDirectories();
  }

  /**
   * Handle instance deletion
   */
  private handleDeleted(message: { guid: string }): void {
    const { guid } = message;
    const node = this.tree.getNode(guid);

    // If the node is already gone (e.g., child deletes after parent delete), fall back to full cleanup
    if (!node) {
      log.debug(`Delete ignored for unknown guid: ${guid}`);
      this.fileWriter.deleteScript(guid);
      // this.regenerateSourcemap();
      this.cleanupDirectories();
      return;
    }

    // Capture all script descendants (and the node itself if script) before we delete the tree nodes
    const scriptsToDelete: { guid: string; filePath: string | null }[] = [];
    const collectScript = (scriptNode: TreeNode): void => {
      const filePath = this.fileWriter.getFilePath(scriptNode);
      scriptsToDelete.push({ guid: scriptNode.guid, filePath });
    };

    if (this.isScriptClass(node.className)) {
      collectScript(node);
    }
    for (const child of this.tree.getDescendantScripts(node.guid)) {
      collectScript(child);
    }

    const pathSegments = node.path;

    // Delete from tree (removes node and descendants)
    this.tree.deleteInstance(guid);

    // Delete files for all affected scripts
    for (const entry of scriptsToDelete) {
      const removed = this.fileWriter.deleteScript(entry.guid);
      if (!removed && entry.filePath) {
        this.fileWriter.deleteFilePath(entry.filePath);
      }
    }

    // Remove subtree from sourcemap
    const outputPath = config.sourcemapPath;
    const pruned = this.sourcemapGenerator.prunePath(
      pathSegments,
      outputPath,
      this.tree.getAllNodes(),
      this.fileWriter.getAllMappings(),
      node.className,
      node.guid,
    );

    // If prune failed to find the path (e.g., sourcemap drift), rebuild once to stay consistent
    if (!pruned) {
      if (this.batchDepth > 0) {
        // Defer regeneration until the batch completes to avoid repeated full rebuilds
        this.batchNeedsSourcemapRegen = true;
        log.debug("Regenerating sourcemap after batched prune miss");
      } else {
        log.debug("Regenerating sourcemap due to prune miss");
        this.regenerateSourcemap();
      }
    }

    if (node.parentGuid) {
      const siblingScriptNodes = this.tree.getDescendantScripts(
        node.parentGuid,
      );
      const sameNameScriptNodes = siblingScriptNodes.filter(
        (sibling) =>
          sibling.parent?.guid === node.parentGuid &&
          sibling.name === node.name,
      );

      for (const scriptToRename of sameNameScriptNodes) {
        if (scriptToRename.path.length !== 0) {
          const newFilePath = this.fileWriter.getFilePath(scriptToRename);

          // Write new path
          this.fileWatcher.suppressNextChange(
            newFilePath,
            scriptToRename.source,
          );
          this.fileWriter.writeScript(scriptToRename);

          // Upsert the subtree into the sourcemap
          this.sourcemapGenerator.upsertSubtree(
            scriptToRename,
            this.tree.getAllNodes(),
            this.fileWriter.getAllMappings(),
            config.sourcemapPath,
            undefined,
            false,
          );
        }
      }
    }

    this.cleanupDirectories();
  }

  /**
   * Helper to get relative paths of all active folder/instance nodes in TreeManager
   */
  private getActiveFolderPaths(): Set<string> {
    const paths = new Set<string>();
    for (const node of this.tree.getAllNodes().values()) {
      if (node.path && node.path.length > 0) {
        // Sanitize each segment the same way FileWriter does.
        // Makes sure that the paths we use match the actual on-disk paths.
        const sanitized = node.path.map((segment) =>
          this.fileWriter.sanitizeSegment(segment),
        );
        paths.add(sanitized.join("/"));
        for (let i = 1; i < sanitized.length; i++) {
          paths.add(sanitized.slice(0, i).join("/"));
        }
      }
    }
    return paths;
  }

  /**
   * Safe cleanup of empty directories that preserves active instance folders
   */
  private cleanupDirectories(): void {
    this.fileWriter.cleanupEmptyDirectories(this.getActiveFolderPaths());
  }

  /**
   * Handle file change from filesystem
   */
  private handleFileChange(filePath: string, source: string): void {
    // Find the GUID for this file
    const guid = this.fileWriter.getGuidByPath(filePath);

    if (guid) {
      log.script(
        `${path.relative(this.fileWriter.getBaseDir(), filePath)} (external)`,
        "updated",
      );

      // Same-source anti-echo should be handled in watcher.ts, this is just in case
      const node = this.tree.getNode(guid);
      if (node?.source === source) {
        log.debug(
          `Skipping Studio patch for unchanged file: ${path.relative(this.fileWriter.getBaseDir(), filePath)}.`,
        );
        return;
      }

      // Update tree
      this.tree.updateScriptSource(guid, source);

      // Send patch to Studio (WebSocket client)
      this.ipc.patchScript(guid, source);
    } else {
      log.warn(`No mapping found for file: ${filePath}`);
    }
  }

  /**
   * Helper to parse relative path segments inside syncDir
   */
  private getRelativeSegments(absPath: string): string[] {
    const baseDir = path.resolve(this.fileWriter.getBaseDir());
    const rel = path.relative(baseDir, absPath);
    if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) {
      return [];
    }
    return rel.split(/[/\\]/).filter(Boolean);
  }

  /**
   * Handle new file creation on filesystem
   */
  private handleFileAdd(filePath: string, source: string): void {
    if (!config.liveFsSync.enabled) return;

    const existingGuid = this.fileWriter.getGuidByPath(filePath);
    if (existingGuid) {
      log.debug(`File add ignored, already mapped: ${filePath}`);
      return;
    }

    const segments = this.getRelativeSegments(filePath);
    if (segments.length === 0) return;

    const dirSegments = segments.slice(0, -1);
    const fileName = segments[segments.length - 1];

    // A file creation may actually be the destination of a script rename/move.
    // The inode is preserved across a rename, so if this new file's inode
    // matches a buffered delete, move the existing instance instead of
    // creating a fresh one — this preserves every descendant (script and
    // non-script alike) under the moved script.
    const inode = this.statInode(filePath);
    const pending = inode ? this.pendingInstanceDeletes.get(inode) : undefined;
    if (pending) {
      const movedName = classifyScriptFileName(fileName, {
        stripDisambiguationSuffix: true,
      }).scriptName;
      this.performInstanceMove(pending.guid, pending.oldSegments, [
        ...dirSegments,
        movedName,
      ]);
      return;
    }

    // Rojo developers may do init.luau; warn them about Azul's behavior!
    if (isInitScriptFileName(fileName)) {
      const relPath = path.relative(this.fileWriter.getBaseDir(), filePath);
      const normalized = normalizeLuaLikeFileName(fileName).toLowerCase();

      let siblingSuffix = ".luau"; // init.luau -> ModuleScript
      if (normalized === "init.server.luau") {
        siblingSuffix = ".server.luau"; // -> Script
      } else if (normalized === "init.client.luau") {
        siblingSuffix = ".client.luau"; // -> LocalScript
      }

      const folderName = dirSegments[dirSegments.length - 1];

      if (!folderName) {
        log.warn(`'${relPath}': Azul does not use the init.luau pattern!`);
        log.warn(
          `To create a script, name the file after the instance (e.g. 'MyScript${siblingSuffix}') instead of 'init'.`,
        );
      } else {
        log.warn(`'${relPath}': Azul does not use the init.luau pattern!`);
        log.warn(
          `To make '${folderName}' a script with children, create a sibling file '${folderName}${siblingSuffix}' next to the '${folderName}/' folder (not inside it). '${folderName}/' will now contain the children of '${folderName}${siblingSuffix}'.`,
        );
        log.warn(
          `More info: https://azul.ransomwave.games/sync-details/#nested-scripts`,
        );
      }

      // return;
    }

    const classified = classifyScriptFileName(fileName, {
      stripDisambiguationSuffix: true,
    });

    log.info(
      `File created externally: ${path.relative(this.fileWriter.getBaseDir(), filePath)}`,
    );

    this.ipc.createInstance(
      classified.className,
      classified.scriptName,
      dirSegments,
      source,
    );
  }

  /**
   * Handle file deletion on filesystem
   */
  private handleFileDelete(filePath: string): void {
    if (!config.liveFsSync.enabled) return;

    const guid = this.fileWriter.getGuidByPath(filePath);

    if (guid) {
      // Tracked script: buffer the delete so a matching file creation can turn
      // it into an instance move instead of a destructive delete+recreate.
      // Without this, Studio's Destroy() would cascade and destroy every
      // descendant (script and non-script alike) under this script.
      //
      // Use the tree's own path for this guid rather than re-deriving it from
      // the raw filename — the filename still carries the .server/.client/.luau
      // suffix, which isn't part of the DataModel path.
      const relPath = this.getRelativeSegments(filePath);
      const oldSegments = this.tree.getNode(guid)?.path ?? relPath;
      const key = this.guidToInode.get(guid) ?? `guid:${guid}`;
      const previous = this.pendingInstanceDeletes.get(key);
      if (previous) {
        clearTimeout(previous.timer);
        log.debug(
          `Resetting pending delete for ${relPath.join("/")}; still waiting for a matching add`,
        );
      } else {
        log.debug(
          `Buffering delete for ${relPath.join("/")}; waiting for a matching add`,
        );
      }
      const timer = setTimeout(
        () => this.flushPendingDelete(key, guid, oldSegments),
        this.moveWindowMs,
      );
      this.pendingInstanceDeletes.set(key, {
        guid,
        oldSegments,
        timer,
      });
    } else {
      log.info(
        `File deleted externally: ${path.relative(this.fileWriter.getBaseDir(), filePath)}`,
      );

      const segments = this.getRelativeSegments(filePath);
      if (segments.length === 0) return;

      const dirSegments = segments.slice(0, -1);
      const fileName = segments[segments.length - 1];
      const classified = classifyScriptFileName(fileName, {
        stripDisambiguationSuffix: true,
      });
      const instancePath = [...dirSegments, classified.scriptName];

      this.ipc.deleteInstance(undefined, instancePath);
    }
  }

  /**
   * A directory whose name matches a sibling script file is not a Folder — it is
   * the children-container of that script (Azul's nested-scripts convention:
   * `Foo.server.luau` + `Foo/`). Such directories must not map to Folder instances.
   */
  private isScriptChildContainer(dirPath: string): boolean {
    const parentDir = path.dirname(dirPath);
    const folderName = path.basename(dirPath);

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(parentDir, { withFileTypes: true });
    } catch {
      return false;
    }

    for (const entry of entries) {
      if (!entry.isFile() || !isScriptFileName(entry.name)) continue;
      const classified = classifyScriptFileName(entry.name, {
        stripDisambiguationSuffix: true,
      });
      if (classified.scriptName === folderName) {
        return true;
      }
    }

    return false;
  }

  /**
   * Handle directory creation on filesystem
   */
  private handleDirAdd(dirPath: string): void {
    if (!config.liveFsSync.enabled) return;

    const segments = this.getRelativeSegments(dirPath);
    if (segments.length === 0) return;

    const parentPath = segments.slice(0, -1);
    const folderName = segments[segments.length - 1];

    // A directory alongside a same-named script is that script's children
    // container, not a Folder instance. Creating a Folder here would spawn a
    // spurious duplicate of the script's name in Studio.
    if (this.isScriptChildContainer(dirPath)) {
      log.debug(
        `Directory '${folderName}' is a script children container; not creating a Folder instance`,
      );
      return;
    }

    // A directory creation may actually be the destination of a folder
    // rename/move. The inode is preserved across a rename, so if this new
    // directory's inode matches a buffered folder deletion, move the existing
    // instance instead of creating a fresh Folder — this preserves non-script
    // descendants that have no filesystem representation.
    const inode = this.statInode(dirPath);
    const pending = inode ? this.pendingInstanceDeletes.get(inode) : undefined;
    if (pending) {
      this.performInstanceMove(pending.guid, pending.oldSegments, segments);
      return;
    }

    log.info(
      `Directory created externally: ${path.relative(this.fileWriter.getBaseDir(), dirPath)}`,
    );

    this.ipc.createInstance("Folder", folderName, parentPath);
  }

  /**
   * Handle directory deletion on filesystem
   */
  private handleDirDelete(dirPath: string): void {
    if (!config.liveFsSync.enabled) return;

    const segments = this.getRelativeSegments(dirPath);
    if (segments.length === 0) return;

    // If a same-named script file still exists, this directory was that script's
    // children container — deleting it must not delete the script instance
    // (its children were already removed via their own unlink events).
    if (this.isScriptChildContainer(dirPath)) {
      log.debug(
        `Directory '${segments[segments.length - 1]}' is a script children container; not deleting an instance`,
      );
      return;
    }

    const node = this.findTrackedFolderNode(segments);
    if (!node) {
      // Untracked folder (created and removed purely on disk): nothing in Studio
      // to lose, delete immediately.
      log.info(
        `Directory deleted externally: ${path.relative(this.fileWriter.getBaseDir(), dirPath)}`,
      );
      this.ipc.deleteInstance(undefined, segments);
      return;
    }

    // Tracked folder: buffer the delete so a matching directory creation can turn
    // it into an instance move. Without this, deleting the folder in Studio
    // cascades and destroys non-script descendants that can't be rebuilt from disk.
    // Key by the folder's inode (recorded while its directory still existed) so a
    // matching addDir can claim it regardless of per-file event ordering.
    const key = this.guidToInode.get(node.guid) ?? `guid:${node.guid}`;
    const previous = this.pendingInstanceDeletes.get(key);
    if (previous) {
      clearTimeout(previous.timer);
      log.debug(
        `Resetting pending folder delete for ${segments.join("/")}; still waiting for a matching addDir`,
      );
    } else {
      log.debug(
        `Buffering folder delete for ${segments.join("/")}; waiting for a matching addDir`,
      );
    }
    const timer = setTimeout(
      () => this.flushPendingDelete(key, node.guid, segments),
      this.moveWindowMs,
    );
    this.pendingInstanceDeletes.set(key, {
      guid: node.guid,
      oldSegments: segments,
      timer,
    });
  }

  /** Find a tracked non-script folder node at the given path, if any. */
  private findTrackedFolderNode(segments: string[]): TreeNode | undefined {
    for (const node of this.tree.getAllNodes().values()) {
      if (
        node.className === "DataModel" ||
        this.isScriptClass(node.className)
      ) {
        continue;
      }
      if (
        node.path.length === segments.length &&
        node.path.every((s, i) => s === segments[i])
      ) {
        return node;
      }
    }
    return undefined;
  }

  /**
   * Find any tracked node at the given path, including scripts. A script's own
   * nested descendants (Azul's nested-scripts convention) have that script as
   * their Roblox parent, so resolving a move's destination parent needs this,
   * not findTrackedFolderNode.
   */
  private findTrackedNode(segments: string[]): TreeNode | undefined {
    for (const node of this.tree.getAllNodes().values()) {
      if (node.className === "DataModel") {
        continue;
      }
      if (
        node.path.length === segments.length &&
        node.path.every(
          (segment, i) =>
            this.fileWriter.sanitizeSegment(segment) === segments[i],
        )
      ) {
        return node;
      }
    }
    return undefined;
  }

  /** The inode of a path as a string key, or null if it can't be stat'd. */
  private statInode(absPath: string): string | null {
    try {
      const { ino } = fs.statSync(absPath);
      // Some filesystems (FAT/exFAT, certain network/virtual mounts) don't
      // support file IDs and report 0 for every entry. Treating that as a real
      // ID would collapse unrelated folders onto the same key and could make
      // performFolderMove reparent the wrong instance
      if (!ino) return null;
      return String(ino);
    } catch {
      return null;
    }
  }

  /**
   * Record inode→guid for a node whose filesystem path currently exists — a
   * script's file, or a folder's directory. Used to recognize a later
   * rename/move (matched by inode) instead of treating it as delete+recreate.
   */
  private recordInode(node: TreeNode): void {
    if (node.className === "DataModel") {
      return;
    }
    const inode = this.statInode(this.fileWriter.getFilePath(node));
    if (inode) this.guidToInode.set(node.guid, inode);
  }

  /** Record inodes for every tracked node that has a file/directory on disk. */
  private recordInodes(): void {
    for (const node of this.tree.getAllNodes().values()) {
      this.recordInode(node);
    }
  }

  /** A buffered delete fired without a matching move: delete for real. */
  private flushPendingDelete(
    key: string,
    guid: string,
    oldSegments: string[],
  ): void {
    this.pendingInstanceDeletes.delete(key);

    // Backstop: if the node has moved to a different path since buffering, it was
    // a rename/move handled elsewhere — never delete an instance that relocated.
    const node = this.tree.getNode(guid);
    if (node && !this.pathsEqualSegments(node.path, oldSegments)) return;

    this.guidToInode.delete(guid);
    log.info(`Instance deleted externally: ${oldSegments.join("/")}`);

    // Only prune local state once Studio actually received the delete.
    if (this.ipc.deleteInstance(guid)) {
      this.handleDeleted({ guid });
    } else {
      log.warn(
        `Studio did not receive the delete for ${guid}; keeping local state`,
      );
    }
  }

  /**
   * Turn a buffered delete + matching filesystem creation into a move. Handles
   * both folders (a directory rename/move) and scripts (a file rename/move) —
   * in either case Studio reparents/renames the existing instance rather than
   * destroying and recreating it, so descendants that have no filesystem
   * representation (Parts, Models, ...) survive.
   */
  private performInstanceMove(
    guid: string,
    oldSegments: string[],
    newSegments: string[],
  ): void {
    const newName = newSegments[newSegments.length - 1];
    const node = this.tree.getNode(guid);

    // Move the existing instance in Studio, preserving its GUID and every
    // descendant (scripts and non-scripts alike).
    this.ipc.moveInstance(guid, newSegments.slice(0, -1), newName);

    // Resolve the destination parent from the NEW location. Without an explicit
    // parentGuid, updateInstance treats the parent as unchanged and leaves the
    // node attached under its OLD parent in the tree graph, only node.path
    // would reflect the move. That desync is invisible for a same-parent
    // rename, but for a cross-parent move it means a later delete of the old
    // parent would wrongly cascade-delete this already-moved subtree.
    const destinationParent = this.findTrackedNode(newSegments.slice(0, -1));

    // Reflect the move in the tree so descendant paths are recalculated. This
    // also arms the backstop for any descendant instances that moved along.
    this.tree.updateInstance({
      guid,
      className: node?.className ?? "Folder",
      name: newName,
      path: newSegments,
      parentGuid: destinationParent?.guid,
    });

    const moved = this.tree.getNode(guid);

    // For a moved script, the physical file already exists at newSegments (the
    // OS move put it there) but FileWriter's own mapping still points at the
    // old path. Without updating it, getGuidByPath(newPath) would miss, and a
    // later content edit to this same file would be silently dropped.
    if (moved && this.isScriptClass(moved.className)) {
      const newFilePath = this.fileWriter.getFilePath(moved);
      this.fileWatcher.suppressNextChange(newFilePath, moved.source);
      this.fileWriter.remapScript(guid, newFilePath, moved.className);

      // A script with descendant scripts stores them in a sibling directory
      // sharing its base name (Azul's nested-scripts convention: Module.luau +
      // Module/). That directory has no tree node of its own — it's purely
      // derived from each descendant's own path — so it doesn't follow the
      // script's move/rename automatically. Move it alongside now, instead of
      // leaving it orphaned until each descendant is individually re-edited.
      this.relocateScriptChildrenFolder(guid, oldSegments, newSegments);
    } else if (moved) {
      // OS already moved these files; FileWriter's mapping hasn't caught up.
      // Remap now, or each descendant's unlink/add reads as an unrelated
      // delete+create (harmless, but sourcemap stays stale for a round-trip).
      for (const descendant of this.tree.getDescendantScripts(guid)) {
        const oldFilePath = this.fileWriter.getMapping(
          descendant.guid,
        )?.filePath;
        const newFilePath = this.fileWriter.getFilePath(descendant);
        if (oldFilePath) {
          this.fileWatcher.suppressNextEvent(oldFilePath, "unlink");
        }
        this.fileWatcher.suppressNextEvent(newFilePath, "add");
        this.fileWriter.remapScript(
          descendant.guid,
          newFilePath,
          descendant.className,
        );
      }
    }

    // Descendants moved with this instance — cancel their buffered deletes.
    for (const [key, entry] of this.pendingInstanceDeletes) {
      if (
        entry.guid === guid ||
        this.pathsEqualSegments(entry.oldSegments, oldSegments) ||
        this.segmentsUnder(entry.oldSegments, oldSegments)
      ) {
        clearTimeout(entry.timer);
        this.pendingInstanceDeletes.delete(key);
      }
    }

    if (moved) {
      this.sourcemapGenerator.upsertSubtree(
        moved,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings(),
        config.sourcemapPath,
        oldSegments,
        false,
      );
    }
    this.cleanupDirectories();

    // Same parent, different name = a rename; different parent = a move.
    // Detection can't tell these apart upfront (both are just an inode-matched
    // unlink+add pair), so decide the wording from the resulting segments.
    const sameParent = this.pathsEqualSegments(
      oldSegments.slice(0, -1),
      newSegments.slice(0, -1),
    );
    const action = sameParent ? "Renamed" : "Moved";
    log.info(
      `${action} externally (${moved?.className ?? "?"}): ${oldSegments.join("/")} -> ${newSegments.join("/")}`,
    );
  }

  /**
   * Move a script's nested-scripts children-container directory (if it has
   * one) to sit alongside its new file location, and remap every descendant
   * script's file mapping to match. A failure here is non-fatal — the script
   * itself already moved successfully — it's just left at the old location
   * until it self-heals on the next edit of each descendant.
   */
  private relocateScriptChildrenFolder(
    guid: string,
    oldSegments: string[],
    newSegments: string[],
  ): void {
    const oldFolderPath = this.fileWriter.getDirPathForSegments(oldSegments);
    const newFolderPath = this.fileWriter.getDirPathForSegments(newSegments);

    if (oldFolderPath === newFolderPath || !fs.existsSync(oldFolderPath)) {
      return;
    }

    // Snapshot descendants' current file paths before anything moves.
    // FileWriter's mapping table is independent of tree.path (already updated
    // to the new location by the caller), so this still reflects where each
    // descendant's file currently sits on disk.
    const descendants = this.tree.getDescendantScripts(guid);
    const oldFilePaths = new Map<string, string | undefined>();
    for (const descendant of descendants) {
      oldFilePaths.set(
        descendant.guid,
        this.fileWriter.getMapping(descendant.guid)?.filePath,
      );
    }

    this.fileWatcher.suppressNextEvent(oldFolderPath, "unlinkDir");
    this.fileWatcher.suppressNextEvent(newFolderPath, "addDir");

    try {
      fs.mkdirSync(path.dirname(newFolderPath), { recursive: true });
      fs.renameSync(oldFolderPath, newFolderPath);
    } catch (error) {
      log.warn(
        `Failed to relocate children folder for moved instance ${guid} (left at old location):`,
        error,
      );
      return;
    }

    for (const descendant of descendants) {
      const oldFilePath = oldFilePaths.get(descendant.guid);
      const newFilePath = this.fileWriter.getFilePath(descendant);
      if (oldFilePath)
        this.fileWatcher.suppressNextEvent(oldFilePath, "unlink");
      this.fileWatcher.suppressNextEvent(newFilePath, "add");
      this.fileWriter.remapScript(
        descendant.guid,
        newFilePath,
        descendant.className,
      );
    }

    log.info(
      `Relocated children folder: ${path.relative(this.fileWriter.getBaseDir(), oldFolderPath)} -> ${path.relative(this.fileWriter.getBaseDir(), newFolderPath)}`,
    );
  }

  private pathsEqualSegments(a: string[], b: string[]): boolean {
    return a.length === b.length && a.every((s, i) => s === b[i]);
  }

  /** True if `inner` is strictly nested under `outer`. */
  private segmentsUnder(inner: string[], outer: string[]): boolean {
    return inner.length > outer.length && outer.every((s, i) => s === inner[i]);
  }

  /**
   * Regenerate the sourcemap
   */
  private regenerateSourcemap(): void {
    // Write sourcemap into the sync directory so Luau-LSP can find it
    const outputPath = config.sourcemapPath;
    this.sourcemapGenerator.generateAndWrite(
      this.tree.getAllNodes(),
      this.fileWriter.getAllMappings(),
      outputPath,
    );
  }

  /**
   * Start the daemon
   */
  public start(): void {
    log.info("🚀 Azul daemon starting...");
    log.info(`Sync directory: ${config.syncDir}`);
    log.info(`HTTP/WebSocket port: ${config.port}`);
    log.info("");
    log.success(`Server listening on http://localhost:${config.port}`);
    log.info("Waiting for Studio connection...");
  }

  /**
   * Stop the daemon
   */
  public async stop(): Promise<void> {
    if (this.stopPromise) {
      return this.stopPromise;
    }

    this.stopPromise = (async () => {
      log.info("Stopping daemon...");
      for (const entry of this.pendingInstanceDeletes.values()) {
        clearTimeout(entry.timer);
      }
      this.pendingInstanceDeletes.clear();
      this.guidToInode.clear();
      await this.fileWatcher.stop();
      this.ipc.send({ type: "daemonDisconnect" });
      await new Promise((resolve) => setTimeout(resolve, 50));
      this.ipc.close();
      await new Promise<void>((resolve, reject) => {
        this.httpServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
      log.info("Daemon stopped");
    })();

    return this.stopPromise;
  }

  private isScriptClass(className: string): boolean {
    return (
      className === "Script" ||
      className === "LocalScript" ||
      className === "ModuleScript"
    );
  }

  /**
   * Delete files under syncDir that are not mapped to any instance (opt-in).
   */
  private cleanupOrphanFiles(): void {
    if (!config.deleteOrphansOnConnect) {
      return;
    }

    const baseDir = this.fileWriter.getBaseDir();
    const mapped = new Set<string>();

    for (const mapping of this.fileWriter.getAllMappings().values()) {
      mapped.add(path.resolve(mapping.filePath));
    }

    let removedFiles: string[] = [];

    const walk = (dir: string): void => {
      if (!fs.existsSync(dir)) return;
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          walk(fullPath);
        } else {
          if (!mapped.has(path.resolve(fullPath))) {
            try {
              fs.unlinkSync(fullPath);
              removedFiles.push(entry.name);
            } catch (error) {
              log.warn("Failed to delete orphan file:", fullPath, error);
            }
          }
        }
      }
    };

    walk(baseDir);
    if (removedFiles.length > 0) {
      this.cleanupDirectories();
      log.success(
        `Removed ${removedFiles.length} orphan file(s) from sync directory (${removedFiles.join(", ")})`,
      );
    }
  }
}

// Allow direct execution (`node dist/index.js`) while preventing side effects when imported by the CLI
const isDirectRun =
  process.argv[1] &&
  fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (isDirectRun) {
  initializeConfig();
  const daemon = new SyncDaemon();
  daemon.start();

  // Handle graceful shutdown
  process.on("SIGINT", async () => {
    console.log("\n");
    console.log("Received SIGINT, shutting down...");
    await daemon.stop();
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    await daemon.stop();
    process.exit(0);
  });
}
