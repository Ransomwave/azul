import * as chokidar from "chokidar";
import * as fs from "fs";
import * as path from "path";
import { log } from "../util/log.js";
import { config } from "../config.js";

export type FileChangeHandler = (filePath: string, source: string) => void;

export type FileEventType =
  | "change"
  | "add"
  | "unlink"
  | "addDir"
  | "unlinkDir";

export type FileEventHandler = (
  event: FileEventType,
  filePath: string,
  source?: string,
) => void;

/**
 * Watches the filesystem for changes and notifies handlers
 */
export class FileWatcher {
  private watcher: chokidar.FSWatcher | null = null;
  private changeHandler: FileChangeHandler | null = null;
  private eventHandler: FileEventHandler | null = null;
  private debounceTimers: Map<string, NodeJS.Timeout> = new Map();
  private suppressedUntil: Map<string, number> = new Map();
  private expectedContents: Map<string, string> = new Map();
  // Map of filePath -> Map of event type -> expiry timestamp.
  // TTL'd (unlike a bare Set) because a suppression registered for a directory created before watch() starts (e.g.
  // the initial writeTree()) will never be consumed (ignoreInitial means
  // chokidar never emits addDir for it) and would otherwise sit forever,
  // silently swallowing the first *unrelated* future addDir for that same path.
  private suppressedEvents: Map<string, Map<FileEventType, number>> = new Map();
  private static readonly SUPPRESSION_TTL_MS = 1000;

  /**
   * Start watching a directory
   */
  public watch(directory: string): void {
    if (this.watcher) {
      log.warn("Watcher already running, stopping it first");
      this.stop();
    }

    log.info(`Starting file watcher on: ${directory}`);

    // On Windows, native (fs.watch) watching holds an open handle on every
    // watched subdirectory, which makes the OS reject renaming any folder that
    // contains a watched subfolder (EPERM). Polling avoids those handles.
    const { usePolling, pollInterval } = config.liveFsSync;
    if (usePolling) {
      log.info(`Using polling mode (interval: ${pollInterval}ms)`);
    }

    this.watcher = chokidar.watch(directory, {
      persistent: true,
      ignoreInitial: true,
      usePolling,
      interval: pollInterval,
      binaryInterval: pollInterval,
      awaitWriteFinish: {
        stabilityThreshold: 200,
        pollInterval: 50,
      },
    });

    this.watcher.on("change", (filePath) => {
      this.handleFileEvent("change", filePath);
    });

    this.watcher.on("add", (filePath) => {
      this.handleFileEvent("add", filePath);
    });

    this.watcher.on("unlink", (filePath) => {
      this.handleFileEvent("unlink", filePath);
    });

    this.watcher.on("addDir", (dirPath) => {
      this.handleFileEvent("addDir", dirPath);
    });

    this.watcher.on("unlinkDir", (dirPath) => {
      this.handleFileEvent("unlinkDir", dirPath);
    });

    this.watcher.on("error", (error) => {
      log.error("File watcher error:", error);
    });

    this.watcher.on("ready", () => {
      log.success("File watcher ready");
    });
  }

  /**
   * Handle a file event with debouncing
   */
  private handleFileEvent(event: FileEventType, filePath: string): void {
    const debounceKey = `${event}:${filePath}`;

    // Clear existing timer for this event+file
    const existingTimer = this.debounceTimers.get(debounceKey);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // Set new debounced timer
    const timer = setTimeout(() => {
      this.processFileEvent(event, filePath);
      this.debounceTimers.delete(debounceKey);
    }, config.fileWatchDebounce);

    this.debounceTimers.set(debounceKey, timer);
  }

  /**
   * Process a file event after debouncing
   */
  private processFileEvent(event: FileEventType, filePath: string): void {
    const normalizedPath = path.resolve(filePath);

    // For file events, only process script files
    if (event === "change" || event === "add" || event === "unlink") {
      if (!this.isScriptFile(filePath)) {
        return;
      }
    }

    // Check event-specific suppression (used for daemon-originated operations)
    const suppressedEventsForPath = this.suppressedEvents.get(normalizedPath);
    const suppressionExpiresAt = suppressedEventsForPath?.get(event);
    if (
      suppressedEventsForPath !== undefined &&
      suppressionExpiresAt !== undefined
    ) {
      // Always consume the entry on match (expired or not) so a stale
      // suppression can't linger and swallow a later, unrelated occurrence.
      suppressedEventsForPath.delete(event);
      if (suppressedEventsForPath.size === 0) {
        this.suppressedEvents.delete(normalizedPath);
      }

      if (suppressionExpiresAt > Date.now()) {
        log.debug(
          `File event suppressed (daemon-originated, event-specific): ${event} ${normalizedPath}`,
        );
        return;
      }

      log.debug(
        `Discarding expired suppression, processing normally: ${event} ${normalizedPath}`,
      );
    }

    // For unlink and unlinkDir, file no longer exists — skip content-based checks
    if (event === "unlink" || event === "unlinkDir") {
      log.debug(`File event: ${event} ${normalizedPath}`);
      this.dispatchEvent(event, normalizedPath);
      return;
    }

    // For addDir, no content to read
    if (event === "addDir") {
      log.debug(`File event: ${event} ${normalizedPath}`);
      this.dispatchEvent(event, normalizedPath);
      return;
    }

    // For change and add, read the file content
    try {
      const source = fs.readFileSync(filePath, "utf-8");

      // Skip if this change was produced by a Studio-originated write.
      const expectedSource = this.expectedContents.get(normalizedPath);
      if (expectedSource !== undefined) {
        if (source === expectedSource) {
          log.debug(
            `File event suppressed (Studio-originated content match): ${normalizedPath}`,
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
            `File event suppressed (Studio-originated): ${normalizedPath}`,
          );
          return;
        }

        // Clear the suppression if it's expired
        if (suppressUntil && suppressUntil <= now) {
          this.suppressedUntil.delete(normalizedPath);
          this.expectedContents.delete(normalizedPath);
        }
      }

      log.debug(`File event: ${event} ${normalizedPath}`);
      this.dispatchEvent(event, normalizedPath, source);
    } catch (error) {
      log.error(`Failed to read file for event ${event} ${filePath}:`, error);
    }
  }

  /**
   * Dispatch the event to the appropriate handler
   */
  private dispatchEvent(
    event: FileEventType,
    normalizedPath: string,
    source?: string,
  ): void {
    if (this.eventHandler) {
      this.eventHandler(event, normalizedPath, source);
    } else if (
      this.changeHandler &&
      event === "change" &&
      source !== undefined
    ) {
      // Legacy fallback for existing onChange handler
      this.changeHandler(normalizedPath, source);
    }
  }

  /**
   * Check if a file is a script file
   */
  private isScriptFile(filePath: string): boolean {
    return filePath.endsWith(".lua") || filePath.endsWith(".luau");
  }

  /**
   * Register a handler for file changes (legacy, content-change only)
   */
  public onChange(handler: FileChangeHandler): void {
    this.changeHandler = handler;
  }

  /**
   * Register a unified handler for all file events (change, add, unlink, addDir, unlinkDir)
   */
  public onEvent(handler: FileEventHandler): void {
    this.eventHandler = handler;
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
   * Suppress the next occurrence of a specific event type for a file path.
   * Used when the daemon creates/deletes files and wants to avoid echo.
   */
  public suppressNextEvent(filePath: string, event: FileEventType): void {
    const normalizedPath = path.resolve(filePath);
    let eventMap = this.suppressedEvents.get(normalizedPath);
    if (!eventMap) {
      eventMap = new Map();
      this.suppressedEvents.set(normalizedPath, eventMap);
    }
    eventMap.set(event, Date.now() + FileWatcher.SUPPRESSION_TTL_MS);
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
    this.suppressedEvents.clear();
  }
}
