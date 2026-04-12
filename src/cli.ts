#!/usr/bin/env node
import { resolve, dirname } from "node:path";
import fs from "node:fs";
import { spawn } from "node:child_process";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config, getUserConfigPath, initializeConfig } from "./config.js";
import { log } from "./util/log.js";
import * as ReadLine from "readline";
import { BuildCommand } from "./build.js";
import { PushCommand } from "./push.js";
import { PackCommand } from "./pack.js";
import { fileURLToPath } from "node:url";
import { parseCliArgs } from "./util/cliArgs.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(
  fs.readFileSync(resolve(__dirname, "../package.json"), "utf8"),
);
const { version } = pkg;

let parsedArgs;
try {
  parsedArgs = parseCliArgs(process.argv.slice(2));
} catch (error) {
  log.error(`${error}`);
  process.exit(1);
}

if (parsedArgs.help) {
  console.log(`
Usage:
  azul <command> [options]
  azul build [--from-sourcemap <file>] [--rojo] [--rojo-project <file>]
  azul push [options] [--rojo] [--rojo-project <file>] [--from-sourcemap <file>]
  azul pack [-o <file>] [--scripts-only]
  azul config [--path]

Commands:
  (no command)            Start live sync daemon
  build                   One-time push from filesystem into Studio
  push                    Selective push using mappings (place config or -s/-d)
  pack                    Serialize Studio instance properties into sourcemap.json
  config                  Open the Azul config file in your default editor

Global Options:
  -h, --help              Show this help message
  --version               Show Azul version
  --debug                 Print verbose debug output
  --no-warn               Disable confirmation prompts for dangerous operations
  --sync-dir [PATH]       Directory to sync (default: current directory)
  --port [NUMBER]         Studio connection port

Build Options:
  --from-sourcemap [FILE] Build from sourcemap
  --rojo                  Enable Rojo-compatible parsing
  --rojo-project [FILE]   Use a Rojo project file

Push Options:
  -s, --source [DIR]      Source folder to push
  -d, --destination [PATH] Studio destination path (i.e "ReplicatedStorage.Packages")
  --from-sourcemap [FILE] Push from sourcemap
  --no-place-config       Ignore push mappings from place ModuleScript
  --destructive           Wipe destination children before pushing
  --rojo                  Enable Rojo-compatible parsing
  --rojo-project [FILE]   Use a Rojo project file

Pack Options:
  -o, --output            Sourcemap path to write (default: config.sourcemapPath)
  --scripts-only          Serialize only scripts and their descendants

Config Options:
  --path                  Print config file path
  `);
  process.exit(0);
}

if (parsedArgs.version) {
  log.info(`Azul version: ${version}`);
  process.exit(0);
}

initializeConfig();
log.debug(`Loaded user config from: ${getUserConfigPath()}`);

if (parsedArgs.command === "config") {
  const userConfigPath = getUserConfigPath();

  if (parsedArgs.configPath) {
    console.log(userConfigPath);
    process.exit(0);
  }

  try {
    await openWithDefaultEditor(userConfigPath);
    log.info(`Opened Azul config: ${userConfigPath}`);
  } catch (error) {
    throw new Error(`Failed to open config file: ${error}`);
  }

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
  log.userInput("Continue? (Y/N)");

  await new Promise<void>((resolve) => {
    process.stdin.setEncoding("utf-8");
    const rl = ReadLine.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.on("line", (input) => {
      const answer = input.trim().toLowerCase();
      if (answer === "y" || answer === "yes") {
        rl.close();
        resolve();
      } else if (answer === "n" || answer === "no") {
        log.info("Exiting. Please run azul from your project root.");
        process.exit(0);
      } else {
        log.userInput("Please answer Y (yes) or N (no). Are you sure? (Y/N)");
      }
    });
  });
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

  let applySourcemapProperties = true;
  let useSourcemapAsSource = parsedArgs.fromSourcemap !== undefined;

  if (!hasBuildSpecificOptions) {
    const sourcemapExists = fs.existsSync(config.sourcemapPath);
    if (sourcemapExists) {
      log.userInput(
        `Build directly from ${config.sourcemapPath} (includes non-script instances)? (Y/N)`,
      );
      const useFull = await promptYesNo();
      if (useFull) {
        useSourcemapAsSource = true;
        applySourcemapProperties = false;
      } else {
        log.userInput(
          `Use packed properties/attributes from ${config.sourcemapPath}? (Y/N)`,
        );
        applySourcemapProperties = await promptYesNo();
      }
    } else {
      applySourcemapProperties = false;
      log.info(
        `No sourcemap found at ${config.sourcemapPath}. Build will recreate instances as scripts/folders.`,
      );
    }
  }

  if (!parsedArgs.noWarn) {
    log.warn(
      "WARNING: Building will overwrite matching Studio scripts and create new ones from your local environment. Existing Studio instances will not be deleted. Proceed with caution!",
    );
    log.userInput("Continue with build? (Y/N)");

    await new Promise<void>((resolve) => {
      process.stdin.setEncoding("utf-8");
      const rl = ReadLine.createInterface({
        input: process.stdin,
        output: process.stdout,
      });

      rl.on("line", (input) => {
        const answer = input.trim().toLowerCase();
        if (answer === "y" || answer === "yes") {
          rl.close();
          resolve();
        } else if (answer === "n" || answer === "no") {
          log.info("Exiting build command...");
          process.exit(0);
        } else {
          log.userInput(
            "Please answer Y (yes) or N (no). Continue with build? (Y/N)",
          );
        }
      });
    });
  }

  await new BuildCommand({
    syncDir: config.syncDir,
    rojoMode: parsedArgs.rojo,
    rojoProjectFile: parsedArgs.rojoProject ?? undefined,
    applySourcemapProperties,
    useSourcemapAsSource,
    sourcemapPath: parsedArgs.fromSourcemap,
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

  if (!hasPushSpecificOptions && !parsedArgs.rojo) {
    log.userInput(
      "Use place config from Studio (ServerStorage.Azul.Config)? (Y/N)",
    );
    const useConfig = await promptYesNo();
    interactiveUsePlaceConfig = useConfig;

    if (!useConfig) {
      log.userInput("Source folder to push (e.g., src)?");
      interactiveSource = (await promptLine()).trim() || undefined;
      log.userInput(
        "Destination path (dot or slash separated, e.g., ReplicatedStorage.Packages)?",
      );
      interactiveDest = (await promptLine()).trim() || undefined;
      log.userInput("Destructive push (wipe destination children)? (Y/N)");
      interactiveDestructive = await promptYesNo();
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
    log.userInput(
      `Build push snapshot directly from ${config.sourcemapPath} (includes non-script descendants and ancestors)? (Y/N)`,
    );
    useSourcemapAsSource = await promptYesNo();
    if (useSourcemapAsSource) {
      if (fs.existsSync(config.sourcemapPath)) {
        log.userInput(
          `Apply packed properties/attributes from ${config.sourcemapPath}? (Y/N)`,
        );
        applySourcemapProperties = await promptYesNo();
      } else {
        useSourcemapAsSource = false;
        applySourcemapProperties = false;
        throw new Error(
          `Sourcemap not found at "${config.sourcemapPath}"! Please create one or provide it using the "--from-sourcemap" flag.`,
        );
      }
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
      "WARNING: Destructive push will wipe destination children before applying snapshot. Proceed? (Y/N)",
    );

    await new Promise<void>((resolve) => {
      process.stdin.setEncoding("utf-8");
      const rl = ReadLine.createInterface({
        input: process.stdin,
        output: process.stdout,
      });

      rl.on("line", (input) => {
        const answer = input.trim().toLowerCase();
        if (answer === "y" || answer === "yes") {
          rl.close();
          resolve();
        } else if (answer === "n" || answer === "no") {
          log.info("Exiting push command...");
          process.exit(0);
        } else {
          log.userInput(
            "Please answer Y (yes) or N (no). Continue with destructive push? (Y/N)",
          );
        }
      });
    });
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
    sourcemapPath: parsedArgs.fromSourcemap,
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

function openWithDefaultEditor(targetPath: string): Promise<void> {
  return new Promise((resolvePromise, rejectPromise) => {
    const currentPlatform = process.platform;

    const argsByPlatform: Record<string, string[]> = {
      win32: ["/c", "start", "", targetPath],
      darwin: [targetPath],
      linux: [targetPath],
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
            "Could not open config file because 'xdg-open' is not installed. Install it (i.e: 'sudo apt install xdg-utils' or 'sudo dnf install xdg-utils') and try again.",
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

async function promptPackInteractive(defaultOutputPath: string): Promise<{
  outputPath: string;
  scriptsOnly: boolean;
}> {
  log.info("Interactive mode: configuring 'azul pack'.");
  log.userInput("Serialize everything? (Y/N)");
  const scriptsOnly = !(await promptYesNo());

  if (scriptsOnly) {
    log.info(
      "Scripts-only mode will only serialize Script, LocalScript, and ModuleScript instances and their descendants.",
    );
  }

  log.userInput(
    `Output sourcemap path? (press Enter for '${defaultOutputPath}')`,
  );
  const outputInput = await promptLine();
  const outputPath =
    outputInput.trim() === "" ? defaultOutputPath : outputInput.trim();

  return {
    outputPath,
    scriptsOnly,
  };
}

function promptLine(): Promise<string> {
  return new Promise((resolve) => {
    const rl = ReadLine.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.once("line", (input) => {
      rl.close();
      resolve(input);
    });
  });
}

async function promptYesNo(): Promise<boolean> {
  while (true) {
    const input = (await promptLine()).trim().toLowerCase();
    if (input === "y" || input === "yes") {
      return true;
    }
    if (input === "n" || input === "no") {
      return false;
    }
    log.userInput("Please answer Y (yes) or N (no).");
  }
}
