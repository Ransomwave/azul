import { execSync } from "node:child_process";

const SOURCE_FOLDER = "plugin/Vendor";
const DESTINATION = "ReplicatedFirst.AzulCompanionPlugin.Vendor";

execSync(
  `azul push -s ${SOURCE_FOLDER} -d ${DESTINATION} --rojo --destructive --no-warn`,
  { stdio: "inherit" },
);
