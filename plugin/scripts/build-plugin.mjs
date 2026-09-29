import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// Paths are relative to the plugin folder, which azul runs from
const PLUGIN_DIR = fileURLToPath(new URL("..", import.meta.url));
const SOURCE_FOLDER = "sync/ReplicatedFirst";
const DESTINATION = "ReplicatedFirst";
const SOURCEMAP = "plugin.sourcemap.json";

execSync(
  `azul push -s ${SOURCE_FOLDER} -d ${DESTINATION} --from-sourcemap ${SOURCEMAP} --destructive --no-warn`,
  { stdio: "inherit", cwd: PLUGIN_DIR },
);
