#!/usr/bin/env node
import { dirname, join, relative, resolve } from "node:path";
import fs from "node:fs";
import { spawn } from "node:child_process";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config, getUserConfigPath, initializeConfig } from "./config.js";
import { log } from "./util/log.js";
import { BuildCommand } from "./build.js";
import { PushCommand } from "./push.js";
import { PackCommand } from "./pack.js";
import { parseCliArgs } from "./util/cliArgs.js";
import { getCurrentVersion, getLatestVersion } from "./util/versionUtils.js";
import { prompt } from "./util/prompt.js";

const versionCurrent = getCurrentVersion();

let parsedArgs;
try {
  parsedArgs = parseCliArgs(process.argv.slice(2));
} catch (error) {
  log.error(`${error}`);
  process.exit(1);
}

initializeConfig();
log.debug(`Loaded user config from: ${getUserConfigPath()}`);

if (config.checkForUpdates) {
  void checkForUpdates(versionCurrent);
}

const c = {
  reset: "\x1b[0m",
  dim: "\x1b[2m",
  cyan: "\x1b[36m",
  underline: "\x1b[4m",
  bold: "\x1b[1m",
};

if (parsedArgs.help) {
  console.log(`
${c.bold}Usage:${c.reset}
  ${c.cyan}azul <command> [options]${c.reset}

${c.bold}Commands:${c.reset} 
  ${c.bold}(no command)${c.reset}              Start live sync daemon
  ${c.bold}build${c.reset}                     Mount the entire local project into Studio.
  ${c.bold}push${c.reset}                      Mount a local folder or file into Studio at a specific path
  ${c.bold}pack${c.reset}                      Serialize Studio instance properties into a sourcemap
  ${c.bold}config${c.reset}                    Open the Azul config file in your default editor
  ${c.bold}open-studio${c.reset}               Open Roblox Studio on the place ID recorded in the sourcemap

${c.bold}Global Options:${c.reset}
  -h, --help                Show this help message
  --version                 Show Azul version
  --debug                   Print verbose debug output
  --no-warn                 Disable confirmation prompts for dangerous operations
  --sync-dir <path>         Directory to sync (default: ./sync)
  --port <number>           Studio connection port

${c.bold}Build Options:${c.reset}
  --from-sourcemap <file>   Build from sourcemap
  --destructive             Wipe the entire Studio state before building
  --rojo                    Enable Rojo-compatible parsing
  --rojo-project <file>     Use a Rojo project file

${c.bold}Push Options:${c.reset}
  -s, --source <path>       Source file or folder to push (a script and its
                            same-named sibling folder push together)
  -d, --destination <path>  Studio destination path (i.e "ReplicatedStorage.Packages")
  --from-sourcemap <file>   Push from sourcemap
  --no-place-config         Ignore push mappings from place ModuleScript
  --destructive             Wipe destination children before pushing
  --rojo                    Enable Rojo-compatible parsing
  --rojo-project <file>     Use a Rojo project file

${c.bold}Pack Options:${c.reset}
  -o, --output <file>       Sourcemap path to write (default: config.sourcemapPath)
  --scripts-only            Serialize only scripts and their descendants

${c.bold}Config Options:${c.reset}
  --path                    Print config file path

${c.bold}Open-Studio Options:${c.reset}
  --from-sourcemap <file>   Sourcemap to read the place ID from (default: ./sourcemap.json)
  --place-id <number>       Open this place ID instead of reading a sourcemap
  `);
  process.exit(0);
}

if (parsedArgs.version) {
  log.info(`Azul version: ${versionCurrent}`);
  process.exit(0);
}

if (parsedArgs.command === "config") {
  const userConfigPath = getUserConfigPath();

  if (parsedArgs.configPath) {
    console.log(userConfigPath);
    process.exit(0);
  }

  try {
    await openWithDefaultApp(userConfigPath);
    log.info(`Opened Azul config: ${userConfigPath}`);
  } catch (error) {
    throw new Error(`Failed to open config file: ${error}`);
  }

  process.exit(0);
}

if (parsedArgs.command === "open-studio") {
  const placeId =
    parsedArgs.placeId ?? readPackedPlaceId(parsedArgs.fromSourcemap);

  await openWithDefaultApp(
    `roblox-studio:1+task:EditPlace+placeId:${placeId}+universeId:0`,
  );
  log.info(`Opening Roblox Studio on place ${placeId}...`);

  process.exit(0);
}

// get current running path
const currentPath = process.cwd();
if (
  (currentPath.includes(`\\${config.syncDir}`) ||
    currentPath.includes(`/${config.syncDir}`)) &&
  !parsedArgs.noWarn
) {
  log.warn(
    `Looks like you're trying to run Azul from within a '${config.syncDir}' directory. Running Azul here will create a directory like "/${config.syncDir}/${config.syncDir}/", which may be unintended.`,
  );

  const continueFromSyncDir = await prompt.getYesNoInput("Continue?");

  if (!continueFromSyncDir) {
    log.info("Exiting. Please run azul from your project root.");
    process.exit(0);
  }
}

log.info(`Running azul from: ${currentPath}`);

if (parsedArgs.syncDir) config.syncDir = resolve(parsedArgs.syncDir);
if (parsedArgs.port) config.port = parsedArgs.port;
if (parsedArgs.debug) config.debugMode = true;

log.debug(`Debug mode is on!`);

if (parsedArgs.command === "build") {
  if (!parsedArgs.rojo && fs.existsSync("default.project.json")) {
    log.warn(
      'Detected a default.project.json file! You can enable Rojo compatibility mode by passing the "--rojo" flag.',
    );
  }

  const hasBuildSpecificOptions =
    parsedArgs.rojo ||
    Boolean(parsedArgs.rojoProject) ||
    parsedArgs.fromSourcemap !== undefined;
  // || parsedArgs.destructive;
  // Don't consider passing "--destructive" as enough to bypass interactive mode,
  // since destructive building without a sourcemap is very likely a mistake.

  let applySourcemapProperties = true;
  let useSourcemapAsSource = parsedArgs.fromSourcemap !== undefined;
  let interactiveDestructive = parsedArgs.destructive;
  let interactiveSourcemapPath = parsedArgs.fromSourcemap;

  if (!hasBuildSpecificOptions) {
    const chosenSourcemap = await promptSourcemapChoice("build");
    if (chosenSourcemap) {
      interactiveSourcemapPath = chosenSourcemap;
      const useFull = await prompt.getYesNoInput(
        `Build directly from ${chosenSourcemap} (includes non-script instances)?`,
      );
      if (useFull) {
        useSourcemapAsSource = true;
        applySourcemapProperties = false;
      } else {
        applySourcemapProperties = await prompt.getYesNoInput(
          `Use packed properties/attributes from ${chosenSourcemap}?`,
          true,
        );
      }
    } else {
      applySourcemapProperties = false;
      log.info(
        "Not using a sourcemap. Build will recreate instances as scripts/folders.",
      );
    }

    // Only ask about destructive option if we're building from sourcemap.
    // Destructively building without a sourcemap is very likely a mistake, since it wipes everything in Studio instead of building "on top".
    // This functionality is still possible with the "--destructive" flag if someone really wants it
    if (useSourcemapAsSource || applySourcemapProperties) {
      interactiveDestructive = await prompt.getYesNoInput(
        "Destructive build (wipe everything in Studio & build from scratch)?",
      );
    }
  }

  if (!parsedArgs.noWarn) {
    if (interactiveDestructive) {
      log.warn(
        "CAUTION: This will replace your entire Studio state with your local project (all instances, scripts, and properties). Unsaved Studio work WILL BE LOST.",
      );
    } else {
      log.warn(
        "CAUTION: This will overwrite matching Studio scripts/instances and create new ones from your local project. Instances with no local equivalent will be left untouched.",
      );
    }

    const shouldContinue = await prompt.getYesNoInput("Continue with build?");

    if (!shouldContinue) {
      log.info("Exiting build command...");
      process.exit(0);
    }
  }

  await new BuildCommand({
    syncDir: config.syncDir,
    rojoMode: parsedArgs.rojo,
    rojoProjectFile: parsedArgs.rojoProject ?? undefined,
    applySourcemapProperties,
    useSourcemapAsSource,
    sourcemapPath: interactiveSourcemapPath,
    destructive: interactiveDestructive,
  }).run();

  log.info("Build command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  log.info("Exiting...");

  process.exit(0);
}

if (parsedArgs.command === "push") {
  const usePlaceConfig = !parsedArgs.noPlaceConfig;

  const hasPushSpecificOptions = Boolean(
    parsedArgs.source ||
    parsedArgs.destination ||
    parsedArgs.destructive ||
    !usePlaceConfig ||
    parsedArgs.rojo ||
    parsedArgs.rojoProject ||
    parsedArgs.fromSourcemap,
  );

  let interactiveSource = parsedArgs.source ?? undefined;
  let interactiveDest = parsedArgs.destination ?? undefined;
  let interactiveDestructive = parsedArgs.destructive;
  let interactiveUsePlaceConfig = usePlaceConfig;
  let useSourcemapAsSource =
    !parsedArgs.rojo && parsedArgs.fromSourcemap !== undefined;
  let applySourcemapProperties =
    !parsedArgs.rojo && parsedArgs.fromSourcemap === undefined;
  let interactiveSourcemapPath = parsedArgs.fromSourcemap;

  if (!hasPushSpecificOptions && !parsedArgs.rojo) {
    const useConfig = await prompt.getYesNoInput(
      "Use place config from Studio (ServerStorage.Azul.Config)?",
      true,
    );
    interactiveUsePlaceConfig = useConfig;

    if (!useConfig) {
      interactiveSource =
        (await prompt.getInput("Source folder to push?")).trim() || undefined;
      interactiveDest =
        (
          await prompt.getInput(
            "Destination path (dot or slash separated, e.g., ReplicatedStorage.Packages)?",
          )
        ).trim() || undefined;
      interactiveDestructive = await prompt.getYesNoInput(
        "Destructive push (wipe destination children)?",
      );
    }
  }

  const willUsePlaceConfig =
    !parsedArgs.rojo &&
    interactiveUsePlaceConfig &&
    !(interactiveSource && interactiveDest);

  if (
    !parsedArgs.rojo &&
    parsedArgs.fromSourcemap === undefined &&
    !willUsePlaceConfig
  ) {
    const chosenSourcemap = await promptSourcemapChoice("push");
    if (chosenSourcemap) {
      interactiveSourcemapPath = chosenSourcemap;
      useSourcemapAsSource = await prompt.getYesNoInput(
        `Build push snapshot directly from ${chosenSourcemap} (includes non-script descendants and ancestors)?`,
      );
      applySourcemapProperties = await prompt.getYesNoInput(
        `Apply packed properties/attributes from ${chosenSourcemap}?`,
        true,
      );
    } else {
      useSourcemapAsSource = false;
      applySourcemapProperties = false;
      log.info(
        `Not using sourcemap. Azul will recreate instances as scripts/folders based on your local filesystem structure with default Properties/Attributes.`,
      );
    }
  }

  if (!parsedArgs.rojo && fs.existsSync("default.project.json")) {
    log.info(
      "Detected default.project.json. Azul stays in native mode unless you pass --rojo.",
    );
  }

  if (parsedArgs.destructive && !parsedArgs.noWarn) {
    log.warn(
      "CAUTION: Destructive push will wipe destination children before applying snapshot.",
    );

    const shouldContinue = await prompt.getYesNoInput(
      "Continue with destructive push?",
    );

    if (!shouldContinue) {
      log.info("Exiting push command...");
      process.exit(0);
    }
  }

  await new PushCommand({
    source: interactiveSource ?? undefined,
    destination: interactiveDest ?? undefined,
    destructive: interactiveDestructive,
    usePlaceConfig: parsedArgs.rojo ? false : interactiveUsePlaceConfig,
    rojoMode: parsedArgs.rojo,
    rojoProjectFile: parsedArgs.rojoProject ?? undefined,
    applySourcemapProperties,
    useSourcemapAsSource,
    sourcemapPath: interactiveSourcemapPath,
  }).run();

  log.info("Push command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  process.exit(0);
}

if (parsedArgs.command === "pack") {
  let scriptsOnly = parsedArgs.scriptsOnly;

  const hasPackSpecificOptions = parsedArgs.output !== undefined || scriptsOnly;

  let finalOutputPath = parsedArgs.output ?? config.sourcemapPath;

  if (!hasPackSpecificOptions) {
    const interactive = await promptPackInteractive(config.sourcemapPath);
    finalOutputPath = interactive.outputPath;
    scriptsOnly = interactive.scriptsOnly;
  }

  await new PackCommand({
    outputPath: finalOutputPath,
    scriptsAndDescendantsOnly: scriptsOnly,
  }).run();

  log.info("Pack command completed.");
  process.exit(0);
}

const liveDaemon = new SyncDaemon();
liveDaemon.start();

let liveDaemonStopping = false;
const stopLiveDaemon = async (signal: string): Promise<void> => {
  if (liveDaemonStopping) {
    return;
  }

  liveDaemonStopping = true;
  log.info(`Received ${signal}, shutting down...`);

  try {
    await liveDaemon.stop();
    process.exit(0);
  } catch (error) {
    throw new Error(`Failed to stop daemon cleanly: ${error}`);
  }
};

process.on("SIGINT", () => {
  void stopLiveDaemon("SIGINT");
});

process.on("SIGTERM", () => {
  void stopLiveDaemon("SIGTERM");
});

async function checkForUpdates(currentVersion: string): Promise<void> {
  log.debug("Checking for updates...");
  const latest = await getLatestVersion();
  if (latest && latest !== currentVersion) {
    log.warn(
      `A new version of Azul is available! (${currentVersion} -> ${latest})`,
    );
  }
}

function openWithDefaultApp(target: string): Promise<void> {
  return new Promise((resolvePromise, rejectPromise) => {
    const currentPlatform = process.platform;

    const argsByPlatform: Record<string, string[]> = {
      win32: ["/c", "start", "", target],
      darwin: [target],
      linux: [target],
    };

    const commandByPlatform: Record<string, string> = {
      win32: "cmd",
      darwin: "open",
      linux: "xdg-open",
    };

    const commandName = commandByPlatform[currentPlatform];
    const commandArgs = argsByPlatform[currentPlatform];

    if (!commandName || !commandArgs) {
      rejectPromise(new Error(`Unsupported platform: ${currentPlatform}`));
      return;
    }

    const child = spawn(commandName, commandArgs, {
      detached: true,
      stdio: "ignore",
    });

    child.on("error", (error: NodeJS.ErrnoException) => {
      if (currentPlatform === "linux" && error.code === "ENOENT") {
        rejectPromise(
          new Error(
            "Could not open target because 'xdg-open' is not installed. Install it (i.e: 'sudo apt install xdg-utils' or 'sudo dnf install xdg-utils') and try again.",
          ),
        );
        return;
      }

      rejectPromise(error);
    });

    child.unref();
    resolvePromise();
  });
}

/**
 * Finds every "*sourcemap.json" sitting next to the configured sourcemap path,
 * so projects keeping per-place maps (game.sourcemap.json, ...) can pick one.
 * Returns paths relative to the cwd, configured path first.
 */
function findSourcemaps(): string[] {
  const configured = resolve(config.sourcemapPath);
  const dir = dirname(configured);

  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }

  return entries
    .filter(
      (entry) =>
        entry.isFile() && entry.name.toLowerCase().endsWith("sourcemap.json"),
    )
    .map((entry) => join(dir, entry.name))
    .sort((a, b) =>
      a === configured ? -1 : b === configured ? 1 : a.localeCompare(b),
    )
    .map((file) => relative(process.cwd(), file) || file);
}

/**
 * Asks which sourcemap to use. Only prompts when there's an actual choice to
 * make; returns null when there is no sourcemap to use, either because none
 * were found or because the user opted out.
 */
async function promptSourcemapChoice(action: string): Promise<string | null> {
  const found = findSourcemaps();

  if (found.length === 0) {
    log.info(
      `No sourcemap found in ${dirname(resolve(config.sourcemapPath))}.`,
    );
    return null;
  }

  if (found.length === 1) {
    return found[0]!;
  }

  return prompt.getChoice<string | null>(
    `Which sourcemap should Azul ${action} from?`,
    [
      ...found.map((file) => ({ name: file, value: file as string | null })),
      { name: "Don't use a sourcemap", value: null },
    ],
  );
}

async function promptPackInteractive(defaultOutputPath: string): Promise<{
  outputPath: string;
  scriptsOnly: boolean;
}> {
  log.info("Interactive mode: configuring 'azul pack'.");
  const scriptsOnly = !(await prompt.getYesNoInput(
    "Serialize everything?",
    true,
  ));

  if (scriptsOnly) {
    log.info(
      "Scripts-only mode will only serialize Script, LocalScript, and ModuleScript instances and their descendants.",
    );
  }

  const outputPath = (
    await prompt.getInput("Output sourcemap path?", defaultOutputPath)
  ).trim();

  return {
    outputPath,
    scriptsOnly,
  };
}

/**
 * Reads the place ID `azul pack` serialized under the sourcemap's `_azul` key.
 * Exits with an error if there's nothing usable there.
 */
function readPackedPlaceId(sourcemapPath?: string): number {
  const resolvedPath = resolve(sourcemapPath ?? config.sourcemapPath);

  if (!fs.existsSync(resolvedPath)) {
    log.error(
      `No sourcemap found at "${resolvedPath}". Run 'azul pack' first, or pass --place-id.`,
    );
    process.exit(1);
  }

  let placeId: unknown;
  try {
    placeId = JSON.parse(fs.readFileSync(resolvedPath, "utf8"))?._azul?.placeId;
  } catch (error) {
    log.error(`Failed to parse sourcemap at "${resolvedPath}": ${error}`);
    process.exit(1);
  }

  if (typeof placeId !== "number" || placeId <= 0) {
    log.error(
      `No place ID recorded in "${resolvedPath}"! Re-run 'azul' or 'azul pack' with the place open in Studio (and saved to Roblox), or pass --place-id.`,
    );
    process.exit(1);
  }

  return placeId;
}
