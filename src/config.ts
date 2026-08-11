import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { log } from "./util/log.js";

/**
 * Configuration for the sync daemon
 */

export interface AzulConfig {
  //////// Daemon Settings ////////

  /** WebSocket server port */
  port: number;

  /** Enable debug mode */
  debugMode: boolean;

  //////// Sync Settings ////////

  /** Directory where synced files will be stored (relative to project root) */
  syncDir: string;

  /** Path where sourcemap.json is written (relative to project root) */
  sourcemapPath: string;

  /** File extension for scripts */
  scriptExtension: string;

  /** Debounce delay for file watching (ms) */
  fileWatchDebounce: number;

  /** Delete unmapped files in syncDir after a new connection/full snapshot */
  deleteOrphansOnConnect: boolean;

  /** Suffix ModuleScript names with ".module"? */
  suffixModuleScripts: boolean;

  /** Replicate filesystem actions (create, delete) to Studio during live sync */
  liveFsSync: {
    /** Replicate filesystem create/delete actions to Studio */
    enabled: boolean;

    /**
     * Use polling for file watching instead of native OS events.
     * On Windows, native watching holds open handles on every watched
     * subdirectory, which makes the OS reject renaming any folder that
     * contains a watched subfolder (EPERM). Polling avoids those handles.
     * Defaults to true on Windows, false elsewhere.
     */
    usePolling: boolean;

    /** Interval (ms) used when usePolling is enabled */
    pollInterval: number;
  };

  /** Check for Daemon updates? (Uses NPM API) */
  checkForUpdates: boolean;
}

export const defaultConfig: Readonly<AzulConfig> = {
  port: 8080,
  debugMode: false,
  syncDir: "./sync",
  sourcemapPath: "./sourcemap.json",
  scriptExtension: ".luau",
  fileWatchDebounce: 100,
  deleteOrphansOnConnect: true,
  suffixModuleScripts: false,
  liveFsSync: {
    enabled: true,
    usePolling: process.platform === "win32",
    pollInterval: 100,
  },
  checkForUpdates: true,
};

export const config: AzulConfig = { ...defaultConfig };

let initialized = false;

export function getUserConfigPath(): string {
  const configRoot = getPlatformConfigRoot();
  return path.join(configRoot, "azul", "config.json");
}

export function initializeConfig(): void {
  if (initialized) {
    return;
  }

  initialized = true;

  const configPath = getUserConfigPath();
  ensureUserConfigExists(configPath);

  const userConfig = readUserConfig(configPath);
  if (!userConfig) {
    return;
  }

  addMissingFields(userConfig);

  Object.assign(config, userConfig);
}

function getPlatformConfigRoot(): string {
  if (process.platform === "win32") {
    return process.env.APPDATA ?? path.join(os.homedir(), "AppData", "Roaming");
  }

  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support");
  }

  return process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config");
}

function ensureUserConfigExists(configPath: string): void {
  try {
    const configDir = path.dirname(configPath);
    fs.mkdirSync(configDir, { recursive: true });

    if (!fs.existsSync(configPath)) {
      fs.writeFileSync(
        configPath,
        `${JSON.stringify(defaultConfig, null, 2)}\n`,
        "utf8",
      );
    }
  } catch (error) {
    log.warn("Failed to initialize Azul user config file:", error);
  }
}

function addMissingFields(target: Partial<AzulConfig>): void {
  Object.assign(target, { ...defaultConfig, ...target });

  try {
    const configPath = getUserConfigPath();
    fs.writeFileSync(
      configPath,
      `${JSON.stringify(target, null, 2)}\n`,
      "utf8",
    );
  } catch (error) {
    log.warn("Failed to add missing fields to Azul user config:", error);
  }
}

function readUserConfig(configPath: string): Partial<AzulConfig> | null {
  try {
    const raw = fs.readFileSync(configPath, "utf8");
    const parsed = JSON.parse(raw);

    if (!isRecord(parsed)) {
      return null;
    }

    return sanitizeConfig(parsed);
  } catch (error) {
    log.warn("Failed to read Azul user config file:", error);
    return null;
  }
}

function sanitizeConfig(input: Record<string, unknown>): Partial<AzulConfig> {
  const sanitized: Partial<AzulConfig> = {};

  if (isPositiveInteger(input.port)) {
    sanitized.port = input.port;
  }

  if (typeof input.debugMode === "boolean") {
    sanitized.debugMode = input.debugMode;
  }

  if (isNonEmptyString(input.syncDir)) {
    sanitized.syncDir = input.syncDir;
  }

  if (isNonEmptyString(input.sourcemapPath)) {
    sanitized.sourcemapPath = input.sourcemapPath;
  }

  if (isNonEmptyString(input.scriptExtension)) {
    sanitized.scriptExtension = input.scriptExtension;
  }

  if (isPositiveInteger(input.fileWatchDebounce)) {
    sanitized.fileWatchDebounce = input.fileWatchDebounce;
  }

  if (isRecord(input.liveFsSync)) {
    const fs = input.liveFsSync;
    const liveFsSync = { ...defaultConfig.liveFsSync };
    if (typeof fs.enabled === "boolean") liveFsSync.enabled = fs.enabled;
    if (typeof fs.usePolling === "boolean") liveFsSync.usePolling = fs.usePolling;
    if (isPositiveInteger(fs.pollInterval)) liveFsSync.pollInterval = fs.pollInterval;
    sanitized.liveFsSync = liveFsSync;
  }

  if (typeof input.deleteOrphansOnConnect === "boolean") {
    sanitized.deleteOrphansOnConnect = input.deleteOrphansOnConnect;
  }

  if (typeof input.suffixModuleScripts === "boolean") {
    sanitized.suffixModuleScripts = input.suffixModuleScripts;
  }

  if (typeof input.checkForUpdates === "boolean") {
    sanitized.checkForUpdates = input.checkForUpdates;
  }

  return sanitized;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
