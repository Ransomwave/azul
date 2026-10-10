// Vendors rbx_dom_lua into plugin/Vendor/rbx_dom_lua, pinned to an upstream commit.
// To update: bump UPSTREAM_REF, rerun, then review the resulting git diff.
import { execSync } from "node:child_process";
import { mkdirSync, readdirSync, rmSync } from "node:fs";
import path from "node:path";

const UPSTREAM_REF = "6b0d828ea699f72065328fcc1f01875d71af5489";
const TARBALL = `https://codeload.github.com/rojo-rbx/rbx-dom/tar.gz/${UPSTREAM_REF}`;
const DEST = path.join("plugin", "Vendor", "rbx_dom_lua");

// Exclude test files and allValues.json
const isExcluded = (name) =>
  name.endsWith(".spec.lua") || name === "allValues.json";

// Start clean so files deleted upstream don't linger.
rmSync(DEST, { recursive: true, force: true });
mkdirSync(DEST, { recursive: true });

// GitHub tarballs work for any commit (degit only resolves branch/tag tips).
execSync(
  `curl -fsSL ${TARBALL} | tar -xzf - -C ${DEST} --strip-components=3 rbx-dom-${UPSTREAM_REF}/rbx_dom_lua/src`,
  { stdio: "inherit" },
);

for (const name of readdirSync(DEST).filter(isExcluded)) {
  rmSync(path.join(DEST, name));
  console.log(`pruned ${name}`);
}

console.log(`vendored rbx_dom_lua @ ${UPSTREAM_REF}`);
