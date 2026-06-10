import * as chokidar from "chokidar";
import * as fs from "fs";
import * as path from "path";
import { log } from "../util/log.js";
import { config } from "../config.js";

export type FileWatchAction = "change" | "add" | "unlink";

export type FileChangeHandler = (
  filePath: string,
  source: string | null, // null if the file was deleted
  action: FileWatchAction,
) => void;

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
      this.queueFileEvent(filePath, "change");
    });

    this.watcher.on("add", (filePath) => {
      this.queueFileEvent(filePath, "add");
    });

    this.watcher.on("unlink", (filePath) => {
      this.queueFileEvent(filePath, "unlink");
    });

    this.watcher.on("error", (error) => {
      log.error("File watcher error:", error);
    });

    this.watcher.on("ready", () => {
      log.success("File watcher ready");
    });
  }

  /**
   * Queue a file system event with debouncing
   */
  private queueFileEvent(filePath: string, action: FileWatchAction): void {
    // Clear existing timer for this file to reset the debounce window
    const existingTimer = this.debounceTimers.get(filePath);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // Set new debounced timer
    const timer = setTimeout(() => {
      this.processFileEvent(filePath, action);
      this.debounceTimers.delete(filePath);
    }, config.fileWatchDebounce);

    this.debounceTimers.set(filePath, timer);
  }

  /**
   * Process a file event after debouncing
   */
  private processFileEvent(filePath: string, action: FileWatchAction): void {
    const normalizedPath = path.resolve(filePath);

    // Only process script files
    if (!this.isScriptFile(filePath)) {
      return;
    }

    // Skip if this change was produced by a Studio-originated write.
    const now = Date.now();
    const suppressUntil = this.suppressedUntil.get(normalizedPath);
    if (suppressUntil && suppressUntil > now) {
      log.debug(
        `File action '${action}' suppressed (Studio-originated): ${normalizedPath}`,
      );
      return;
    } else if (suppressUntil && suppressUntil <= now) {
      this.suppressedUntil.delete(normalizedPath);
      this.expectedContents.delete(normalizedPath);
    }

    try {
      let source: string | null = null;

      // Only attempt to read content if the file actually exists
      if (action !== "unlink") {
        if (!fs.existsSync(filePath)) {
          log.debug(`File no longer exists to read: ${normalizedPath}`);
          return;
        }
        source = fs.readFileSync(filePath, "utf-8");

        // Suppress if the contents match what Studio sent down
        const expectedSource = this.expectedContents.get(normalizedPath);
        if (expectedSource !== undefined) {
          if (source === expectedSource) {
            log.debug(
              `File action '${action}' suppressed (Content match): ${normalizedPath}`,
            );
            this.expectedContents.delete(normalizedPath);
            return;
          }
          this.expectedContents.delete(normalizedPath);
        }
      }

      log.debug(
        `File system action [${action.toUpperCase()}]: ${normalizedPath}`,
      );

      if (this.changeHandler) {
        this.changeHandler(normalizedPath, source, action);
      }
    } catch (error) {
      log.error(`Failed to process file event for ${filePath}:`, error);
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
  public suppressNextChange(filePath: string, expectedSource?: string | null): void {
    const normalizedPath = path.resolve(filePath);
    const until = Date.now() + 1000; // 1s window to absorb duplicate events
    this.suppressedUntil.set(normalizedPath, until);

    if (expectedSource !== undefined && expectedSource !== null) {
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
