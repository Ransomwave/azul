/**
 * Configuration for the sync daemon
 */

export const config = {
  /** WebSocket server port */
  port: 8080,

  /** Directory where synced files will be stored */
  syncDir: "./sync",

  /** File extension for scripts */
  scriptExtension: ".luau",

  /** Services to exclude from sync */
  excludedServices: new Set([
    "CoreGui",
    "CorePackages",
    "Players",
    "Chat",
    "LocalizationService",
    "TestService",
    "StudioService",
    "RobloxReplicatedStorage",
    "PluginGuiService",
  ]),

  /** Whether to sync non-script instances (folders, models, etc.) */
  syncNonScripts: true,

  /** Debounce delay for file watching (ms) */
  fileWatchDebounce: 100,

  /** Enable debug logging */
  debug: process.env.DEBUG === "true",
};
