import fs from "node:fs";
import { dirname, join, resolve } from "path";
import { log } from "./log.js";
import { fileURLToPath } from "url";
import { getUserConfigPath } from "../config.js";

const PACKAGE_NAME = "azul-sync";
const VERSION_CACHE_TTL_MS = 60 * 60 * 1000;

type VersionCache = { version: string; checkedAt: number };

function getVersionCachePath(): string {
  return join(dirname(getUserConfigPath()), "version-cache.json");
}

function readVersionCache(): VersionCache | null {
  try {
    return JSON.parse(
      fs.readFileSync(getVersionCachePath(), "utf8"),
    ) as VersionCache;
  } catch {
    return null;
  }
}

/**
 * Stores the latest published version so subsequent commands skip the registry
 * lookup for an hour.
 */
function writeVersionCache(version: string): void {
  try {
    fs.writeFileSync(
      getVersionCachePath(),
      JSON.stringify({ version, checkedAt: Date.now() } satisfies VersionCache),
    );
  } catch (error) {
    log.debug(`Could not write version cache: ${error}`);
  }
}

export async function getLatestVersion(): Promise<string | null> {
  const cached = readVersionCache();
  if (cached && Date.now() - cached.checkedAt < VERSION_CACHE_TTL_MS) {
    log.debug(`Using cached latest version: ${cached.version}`);
    return cached.version;
  }

  try {
    const response = await fetch(
      `https://registry.npmjs.org/${PACKAGE_NAME}/latest`,
      { signal: AbortSignal.timeout(5_000) },
    );

    if (!response.ok) {
      log.warn(`Could not check for updates: ${response.statusText}`);
      return null;
    }

    const data = (await response.json()) as { version: string };

    log.debug(`Latest version of ${PACKAGE_NAME} is ${data.version}`);
    writeVersionCache(data.version);

    return data.version;
  } catch (error) {
    log.warn(`Could not check for updates: ${error}`);
    return null;
  }
}

export function getCurrentVersion(): string {
  const __dirname = dirname(fileURLToPath(import.meta.url));
  const pkg = JSON.parse(
    fs.readFileSync(resolve(__dirname, "../../package.json"), "utf8"), // we need to go up two levels because this file is in src/util
  );

  return pkg.version;
}

/**
 * Daemon and plugin only have to agree on major.minor; patch releases stay
 * compatible.
 */
export function isVersionCompatible(a: string, b: string): boolean {
  const key = (v: string) => v.split(".").slice(0, 2).join(".");
  return key(a) === key(b);
}
