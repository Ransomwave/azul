import fs from "node:fs";
import { dirname, resolve } from "path";
import { log } from "./log.js";
import { fileURLToPath } from "url";

export async function getLatestVersion(
  packageName = "azul-sync",
): Promise<string | null> {
  try {
    const response = await fetch(
      `https://registry.npmjs.org/${packageName}/latest`,
    );

    if (!response.ok) {
      log.warn(`Could not check for updates: ${response.statusText}`);
      return null;
    }

    const data = (await response.json()) as { version: string };

    log.debug(`Latest version of ${packageName} is ${data.version}`);

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
