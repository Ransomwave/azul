import { IPCServer } from "./ipc/server.js";
import { TreeManager } from "./fs/treeManager.js";
import { FileWriter } from "./fs/fileWriter.js";
import { FileWatcher } from "./fs/watcher.js";
import { SourcemapGenerator } from "./sourcemap/generator.js";
import { log } from "./util/log.js";
import { config } from "./config.js";
import type { StudioMessage } from "./ipc/messages.js";

/**
 * Main orchestrator for the Super Studio Sync daemon
 */
class SyncDaemon {
  private ipc: IPCServer;
  private tree: TreeManager;
  private fileWriter: FileWriter;
  private fileWatcher: FileWatcher;
  private sourcemapGenerator: SourcemapGenerator;

  constructor() {
    this.ipc = new IPCServer(config.port);
    this.tree = new TreeManager();
    this.fileWriter = new FileWriter(config.syncDir);
    this.fileWatcher = new FileWatcher();
    this.sourcemapGenerator = new SourcemapGenerator();

    this.setupHandlers();
  }

  /**
   * Set up all event handlers
   */
  private setupHandlers(): void {
    // Handle messages from Studio
    this.ipc.onMessage((message) => this.handleStudioMessage(message));

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
      // Write to filesystem
      this.fileWriter.writeScript(node);

      // Regenerate sourcemap
      this.regenerateSourcemap();
    }
  }

  /**
   * Handle instance update (rename, move, etc.)
   */
  private handleInstanceUpdated(data: any): void {
    // Update tree
    this.tree.updateInstance(data);

    // If it's a script, update the file
    const node = this.tree.getNode(data.guid);
    if (node && node.source) {
      this.fileWriter.writeScript(node);
    }

    // Regenerate sourcemap
    this.regenerateSourcemap();
  }

  /**
   * Handle instance deletion
   */
  private handleDeleted(guid: string): void {
    // Delete from tree
    this.tree.deleteInstance(guid);

    // Delete file
    this.fileWriter.deleteScript(guid);

    // Clean up empty directories
    this.fileWriter.cleanupEmptyDirectories();

    // Regenerate sourcemap
    this.regenerateSourcemap();
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

      // Send patch to Studio
      this.ipc.patchScript(guid, source);
    } else {
      log.warn(`No mapping found for file: ${filePath}`);
    }
  }

  /**
   * Regenerate the sourcemap
   */
  private regenerateSourcemap(): void {
    this.sourcemapGenerator.generateAndWrite(
      this.tree.getAllNodes(),
      this.fileWriter.getAllMappings(),
      "sourcemap.json"
    );
  }

  /**
   * Start the daemon
   */
  public start(): void {
    log.info("🚀 Super Studio Sync daemon starting...");
    log.info(`Sync directory: ${config.syncDir}`);
    log.info(`WebSocket port: ${config.port}`);
    log.info("");
    log.info("Waiting for Studio connection...");
  }

  /**
   * Stop the daemon
   */
  public async stop(): Promise<void> {
    log.info("Stopping daemon...");
    await this.fileWatcher.stop();
    this.ipc.close();
    log.info("Daemon stopped");
  }
}

// Create and start daemon
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
