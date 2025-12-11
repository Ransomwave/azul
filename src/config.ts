/**
 * Configuration for the sync daemon
 */

export const config = {
  /** WebSocket server port */
  port: 8080,

  /** Directory where synced files will be stored (relative to project root) */
  syncDir: "./sync",
  // syncDir: "./",

  /** Path where sourcemap.json is written (relative to project root) */
  sourcemapPath: "./sourcemap.json",

  /** File extension for scripts */
  scriptExtension: ".luau",

  /** Whether to sync non-script instances (folders, models, etc.) */
  syncNonScripts: true,

  /** Debounce delay for file watching (ms) */
  fileWatchDebounce: 100,

  /** Enable debug mode */
  debugMode: true,

  /** Enable debug logging */
  debug: process.env.DEBUG === "true",

  /** Delete unmapped files in syncDir after a new connection/full snapshot */
  deleteOrphansOnConnect: true,
};
