/**
 * Configuration for the sync daemon
 */

export const config = {
  /** WebSocket server port */
  // Default: 8080
  port: 8080,

  /** Directory where synced files will be stored (relative to project root) */
  // Default: "./sync"
  syncDir: "./sync",
  // syncDir: "./",

  /** Path where sourcemap.json is written (relative to project root) */
  // Default: "./sourcemap.json"
  sourcemapPath: "./sourcemap.json",

  /** File extension for scripts */
  // Default: ".luau"
  scriptExtension: ".luau",

  /** Debounce delay for file watching (ms) */
  // Default: 100
  fileWatchDebounce: 100,

  /** Delete unmapped files in syncDir after a new connection/full snapshot */
  // Default: true
  deleteOrphansOnConnect: true,

  /** Enable debug mode */
  // Default: false
  debugMode: false,
};
