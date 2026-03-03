import * as chokidar from "chokidar";
import * as fs from "fs";
import * as path from "path";
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
  private suppressedUntil: Map<string, number> = new Map();
  private expectedContents: Map<string, string> = new Map();

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
    const normalizedPath = path.resolve(filePath);

    // Only process script files
    if (!this.isScriptFile(filePath)) {
      return;
    }

    try {
      const source = fs.readFileSync(filePath, "utf-8");

      // Skip if this change was produced by a Studio-originated write.
      const expectedSource = this.expectedContents.get(normalizedPath);
      if (expectedSource !== undefined) {
        if (source === expectedSource) {
          log.debug(
            `File change suppressed (Studio-originated content match): ${normalizedPath}`,
          );
          this.suppressedUntil.delete(normalizedPath);
          this.expectedContents.delete(normalizedPath);
          return;
        }

        // Expected content mismatched, so this is an external change. Clear stale suppression.
        this.suppressedUntil.delete(normalizedPath);
        this.expectedContents.delete(normalizedPath);
      } else {
        // No expected content, but check if we're still within a suppression window
        const now = Date.now();
        const suppressUntil = this.suppressedUntil.get(normalizedPath);
        if (suppressUntil && suppressUntil > now) {
          log.debug(
            `File change suppressed (Studio-originated): ${normalizedPath}`,
          );
          return;
        }

        // Clear the suppression if it's expired
        if (suppressUntil && suppressUntil <= now) {
          this.suppressedUntil.delete(normalizedPath);
          this.expectedContents.delete(normalizedPath);
        }
      }

      log.debug(`File changed: ${normalizedPath}`);

      if (this.changeHandler) {
        this.changeHandler(normalizedPath, source);
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
   * Suppress the next change event for a specific file path (normalized)
   */
  public suppressNextChange(filePath: string, expectedSource?: string): void {
    const normalizedPath = path.resolve(filePath);
    const until = Date.now() + 1000; // 1s window to absorb duplicate events
    this.suppressedUntil.set(normalizedPath, until);

    if (expectedSource !== undefined) {
      this.expectedContents.set(normalizedPath, expectedSource);
    } else {
      this.expectedContents.delete(normalizedPath);
    }
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
    this.suppressedUntil.clear();
    this.expectedContents.clear();
  }
}
