import * as chokidar from "chokidar";
import * as fs from "fs";
import { log } from "../util/log.js";
import { config } from "../config.js";

export type FileChangeHandler = (filePath: string, source: string) => void;

/**
 * Watches the filesystem for changes and notifies handlers
 */
export class FileWatcher {
  private watcher: chokidar.FSWatcher | null = null;
  private changeHandler: FileChangeHandler | null = null;
  private debounceTimers: Map<string, NodeJS.Timeout> = new Map();

  /**
   * Start watching a directory
   */
  public watch(directory: string): void {
    if (this.watcher) {
      log.warn("Watcher already running, stopping it first");
      this.stop();
    }

    log.info(`Starting file watcher on: ${directory}`);

    this.watcher = chokidar.watch(directory, {
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 100,
        pollInterval: 50,
      },
    });

    this.watcher.on("change", (filePath) => {
      this.handleFileChange(filePath);
    });

    this.watcher.on("error", (error) => {
      log.error("File watcher error:", error);
    });

    this.watcher.on("ready", () => {
      log.success("File watcher ready");
    });
  }

  /**
   * Handle a file change with debouncing
   */
  private handleFileChange(filePath: string): void {
    // Clear existing timer for this file
    const existingTimer = this.debounceTimers.get(filePath);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // Set new debounced timer
    const timer = setTimeout(() => {
      this.processFileChange(filePath);
      this.debounceTimers.delete(filePath);
    }, config.fileWatchDebounce);

    this.debounceTimers.set(filePath, timer);
  }

  /**
   * Process a file change after debouncing
   */
  private processFileChange(filePath: string): void {
    // Only process script files
    if (!this.isScriptFile(filePath)) {
      return;
    }

    try {
      const source = fs.readFileSync(filePath, "utf-8");
      log.debug(`File changed: ${filePath}`);

      if (this.changeHandler) {
        this.changeHandler(filePath, source);
      }
    } catch (error) {
      log.error(`Failed to read changed file ${filePath}:`, error);
    }
  }

  /**
   * Check if a file is a script file
   */
  private isScriptFile(filePath: string): boolean {
    return filePath.endsWith(".lua") || filePath.endsWith(".luau");
  }

  /**
   * Register a handler for file changes
   */
  public onChange(handler: FileChangeHandler): void {
    this.changeHandler = handler;
  }

  /**
   * Stop watching
   */
  public async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
      log.info("File watcher stopped");
    }

    // Clear all pending timers
    for (const timer of this.debounceTimers.values()) {
      clearTimeout(timer);
    }
    this.debounceTimers.clear();
  }
}
