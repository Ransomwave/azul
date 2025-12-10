import path from "node:path";
import { fileURLToPath } from "node:url";
import * as http from "http";
import { IPCServer } from "./ipc/server.js";
import { HttpPollingServer } from "./ipc/httpPolling.js";
import { TreeManager, TreeNode } from "./fs/treeManager.js";
import { FileWriter } from "./fs/fileWriter.js";
import { FileWatcher } from "./fs/watcher.js";
import { SourcemapGenerator } from "./sourcemap/generator.js";
import { log } from "./util/log.js";
import { config } from "./config.js";
import type { StudioMessage } from "./ipc/messages.js";

/**
 * Main orchestrator for the Azul daemon
 */
export class SyncDaemon {
  private ipc: IPCServer;
  private httpPolling: HttpPollingServer;
  private httpServer: http.Server;
  private tree: TreeManager;
  private fileWriter: FileWriter;
  private fileWatcher: FileWatcher;
  private sourcemapGenerator: SourcemapGenerator;

  constructor() {
    this.tree = new TreeManager();
    this.fileWriter = new FileWriter(config.syncDir);
    this.fileWatcher = new FileWatcher();
    this.sourcemapGenerator = new SourcemapGenerator();
    this.httpPolling = new HttpPollingServer();

    // Create HTTP server that handles both WebSocket upgrades and HTTP polling
    this.httpServer = http.createServer((req, res) => {
      const handled = this.httpPolling.handleRequest(req, res);
      if (!handled) {
        res.writeHead(404);
        res.end("Not found");
      }
    });

    this.ipc = new IPCServer(config.port, this.httpServer);

    this.setupHandlers();
    this.httpServer.listen(config.port);
  }

  /**
   * Set up all event handlers
   */
  private setupHandlers(): void {
    // Handle messages from Studio (WebSocket)
    this.ipc.onMessage((message) => this.handleStudioMessage(message));

    // Handle messages from Studio (HTTP polling)
    this.httpPolling.onMessage((message) => this.handleStudioMessage(message));

    // Handle file changes from filesystem
    this.fileWatcher.onChange((filePath, source) => {
      this.handleFileChange(filePath, source);
    });
  }

  /**
   * Handle incoming messages from Studio
   */
  private handleStudioMessage(message: StudioMessage): void {
    switch (message.type) {
      case "fullSnapshot":
        this.handleFullSnapshot(message.data);
        break;

      case "scriptChanged":
        this.handleScriptChanged(message);
        break;

      case "instanceUpdated":
        this.handleInstanceUpdated(message.data);
        break;

      case "deleted":
        this.handleDeleted(message.guid);
        break;

      case "ping":
        this.ipc.send({ type: "pong" });
        break;

      case "clientDisconnect":
        log.info("Studio requested to close the connection");
        this.ipc.close();
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

    // Start file watching
    this.fileWatcher.watch(this.fileWriter.getBaseDir());

    // Generate sourcemap
    this.regenerateSourcemap();

    // Log statistics
    const stats = this.tree.getStats();
    log.success(
      `Sync complete: ${stats.scriptNodes} scripts, ${stats.totalNodes} total nodes`
    );
  }

  /**
   * Handle script source change
   */
  private handleScriptChanged(message: any): void {
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
      this.fileWatcher.suppressNextChange(filePath);

      // Write to filesystem
      this.fileWriter.writeScript(node);

      // Incrementally update sourcemap entry for this script
      this.sourcemapGenerator.upsertSubtree(
        node,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings(),
        config.sourcemapPath
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

    if (update.pathChanged || update.nameChanged) {
      for (const child of this.tree.getDescendantScripts(node.guid)) {
        scriptsToUpdate.set(child.guid, child);
      }
    }

    for (const scriptNode of scriptsToUpdate.values()) {
      const filePath = this.fileWriter.getFilePath(scriptNode);
      this.fileWatcher.suppressNextChange(filePath);
      this.fileWriter.writeScript(scriptNode);
    }

    if (
      update.pathChanged ||
      update.nameChanged ||
      this.isScriptClass(node.className)
    ) {
      this.sourcemapGenerator.upsertSubtree(
        node,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings(),
        config.sourcemapPath,
        update.prevPath
      );
    }

    this.fileWriter.cleanupEmptyDirectories();
  }

  /**
   * Handle instance deletion
   */
  private handleDeleted(guid: string): void {
    const node = this.tree.getNode(guid);
    const fallbackPath = node ? this.fileWriter.getFilePath(node) : undefined;
    const pathSegments = node ? node.path : undefined;

    // Delete from tree
    this.tree.deleteInstance(guid);

    // Delete file
    const deleted = this.fileWriter.deleteScript(guid);
    if (!deleted && fallbackPath) {
      this.fileWriter.deleteFilePath(fallbackPath);
    }

    // Remove from sourcemap incrementally when we know the path; fallback to full regen if unavailable
    if (pathSegments) {
      const outputPath = config.sourcemapPath;
      this.sourcemapGenerator.prunePath(
        pathSegments,
        outputPath,
        this.tree.getAllNodes(),
        this.fileWriter.getAllMappings()
      );
    } else {
      this.regenerateSourcemap();
    }

    // Clean up empty directories
    this.fileWriter.cleanupEmptyDirectories();
  }

  /**
   * Handle file change from filesystem
   */
  private handleFileChange(filePath: string, source: string): void {
    // Find the GUID for this file
    const guid = this.fileWriter.getGuidByPath(filePath);

    if (guid) {
      log.info(`File changed externally: ${filePath}`);

      // Update tree
      this.tree.updateScriptSource(guid, source);

      // Send patch to Studio (both WebSocket and HTTP polling clients)
      this.ipc.patchScript(guid, source);
      this.httpPolling.broadcast({ type: "patchScript", guid, source });
    } else {
      log.warn(`No mapping found for file: ${filePath}`);
    }
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
      outputPath
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
    log.info("Stopping daemon...");
    await this.fileWatcher.stop();
    this.ipc.close();
    this.httpServer.close();
    log.info("Daemon stopped");
  }

  private isScriptClass(className: string): boolean {
    return (
      className === "Script" ||
      className === "LocalScript" ||
      className === "ModuleScript"
    );
  }
}

// Allow direct execution (`node dist/index.js`) while preventing side effects when imported by the CLI
const isDirectRun =
  process.argv[1] &&
  fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (isDirectRun) {
  const daemon = new SyncDaemon();
  daemon.start();

  // Handle graceful shutdown
  process.on("SIGINT", async () => {
    console.log("\n");
    await daemon.stop();
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    await daemon.stop();
    process.exit(0);
  });
}
