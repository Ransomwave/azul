import fs from "node:fs";
import path from "node:path";

export const PACKAGE_FILE_NAME = "azul.package.json";

/**
 * A package's push defaults, with every path resolved against the package
 * file's directory.
 */
export interface AzulPackage {
  dir: string;
  root: string;
  sourcemap?: string;
}

/**
 * Returns the package file for a source path that is either the package file
 * itself or a directory containing one.
 */
export function findPackageFile(source: string): string | null {
  const resolved = path.resolve(source);
  if (!fs.existsSync(resolved)) return null;

  if (fs.statSync(resolved).isDirectory()) {
    const candidate = path.join(resolved, PACKAGE_FILE_NAME);
    return fs.existsSync(candidate) ? candidate : null;
  }

  return path.basename(resolved) === PACKAGE_FILE_NAME ? resolved : null;
}

/**
 * Writes a package file in `dir`, storing both paths relative to it.
 * @returns The package file's path.
 */
export function writePackageFile(
  dir: string,
  packageRoot: string,
  sourcemapPath: string,
): string {
  const toRelative = (target: string) =>
    `./${path.relative(dir, path.resolve(target)).split(path.sep).join("/")}`;

  const packageFile = path.join(dir, PACKAGE_FILE_NAME);
  fs.writeFileSync(
    packageFile,
    `${JSON.stringify(
      {
        packageRoot: toRelative(packageRoot),
        fromSourcemap: toRelative(sourcemapPath),
      },
      null,
      2,
    )}\n`,
    "utf8",
  );
  return packageFile;
}

/**
 * Reads a package file. Unknown keys are ignored so other tools can share the file.
 * @throws If the file is unreadable or `packageRoot` is missing.
 */
export function loadPackageFile(packageFile: string): AzulPackage {
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(fs.readFileSync(packageFile, "utf8"));
  } catch (error) {
    throw new Error(`Failed to read package file ${packageFile}: ${error}`);
  }

  const dir = path.dirname(packageFile);
  const { packageRoot, fromSourcemap } = raw;

  if (typeof packageRoot !== "string" || packageRoot.trim() === "") {
    throw new Error(`Package file ${packageFile} is missing "packageRoot".`);
  }

  return {
    dir,
    root: path.resolve(dir, packageRoot),
    sourcemap:
      typeof fromSourcemap === "string" && fromSourcemap.trim() !== ""
        ? path.resolve(dir, fromSourcemap)
        : undefined,
  };
}
