// Vendors rbx_dom_lua into plugin/Vendor/rbx_dom_lua, pinned to an upstream commit.
// To update: bump UPSTREAM_REF, rerun, then review the resulting git diff.
import { execSync } from "node:child_process";
import { readdirSync, rmSync } from "node:fs";
import path from "node:path";

const UPSTREAM_REF = "43d1f129f2eb1fd055512f039863ff35ae5a10f1";
const SOURCE = `rojo-rbx/rbx-dom/rbx_dom_lua/src#${UPSTREAM_REF}`;
const DEST = path.join("plugin", "Vendor", "rbx_dom_lua");

// Exclude test files and allValues.json
const isExcluded = (name) =>
  name.endsWith(".spec.lua") || name === "allValues.json";

// --no keeps this on the exact degit pinned in devDependencies; it errors rather than fetching one.
execSync(`npx --no degit ${SOURCE} ${DEST} --force`, { stdio: "inherit" });

for (const name of readdirSync(DEST).filter(isExcluded)) {
  rmSync(path.join(DEST, name));
  console.log(`pruned ${name}`);
}

console.log(`vendored rbx_dom_lua @ ${UPSTREAM_REF}`);
