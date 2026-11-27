#!/usr/bin/env node
import { basename, dirname, join, relative, resolve } from "node:path";
import fs from "node:fs";
import { spawn } from "node:child_process";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config, getUserConfigPath, initializeConfig } from "./config.js";
import { log } from "./util/log.js";
import { BuildCommand } from "./build.js";
import { PushCommand, parseDestination } from "./push.js";
import { confirmDestinationRoot } from "./util/serviceNames.js";
import {
  findChildPackageDirs,
  findPackageFile,
  loadPackageFile,
  writePackageFile,
} from "./packageFile.js";
import { PackCommand } from "./pack.js";
import {
  buildRojoProject,
  findDefaultProjectFile,
  isGeneratedRojoProject,
  ROJO_PROJECT_FILE_NAME,
  writeRojoProject,
} from "./rojoProject.js";
import { Command, InvalidArgumentError, Option } from "commander";
import { getCurrentVersion, getLatestVersion } from "./util/versionUtils.js";
import { prompt } from "./util/prompt.js";

type GlobalOptions = {
  debug?: boolean;
  warn: boolean;
  syncDir?: string;
  port?: number;
};

type SourceOptions = {
  rojo?: boolean;
  rojoProject?: string;
  fromSourcemap?: string;
  destructive?: boolean;
};

type BuildOptions = GlobalOptions & SourceOptions;

type PushOptions = GlobalOptions &
  SourceOptions & {
    source?: string[];
    destination?: string;
    placeConfig: boolean;
  };

type PackOptions = GlobalOptions & {
  output?: string;
  scriptsOnly?: boolean;
  rojo?: boolean;
  rojoOutput?: string;
};

type OpenStudioOptions = {
  fromSourcemap?: string;
  placeId?: number;
};

const MAX_PORT = 65535;

const versionCurrent = getCurrentVersion();

initializeConfig();
log.debug(`Loaded user config from: ${getUserConfigPath()}`);

if (config.checkForUpdates) {
  await checkForUpdates(versionCurrent);
}

const program = new Command("azul")
  .description("Start the live sync daemon, or run one of the commands below.")
  .version(versionCurrent, "--version", "Show Azul version")
  .helpOption("-h, --help", "Show this help message")
  .option("--debug", "Print verbose debug output")
  .option("--no-warn", "Disable confirmation prompts for dangerous operations")
  .option("--sync-dir <path>", "Directory to sync (default: ./sync)")
  .option(
    "--port <number>",
    "Studio connection port",
    parseNumberInRange(1, MAX_PORT),
  )
  .configureHelp({ showGlobalOptions: true })
  .configureOutput({
    outputError: (message) => log.error(message.replace(/^error: /, "").trim()),
  })
  .action((options: GlobalOptions, command: Command) => {
    if (command.args.length > 0) {
      command.error(`unknown command '${command.args[0]}'`);
    }
    return runDaemon(options);
  });

program
  .command("build")
  .description("Mount the entire local project into Studio")
  .addOption(sourcemapOption("Build from a sourcemap"))
  .option("--destructive", "Wipe the entire Studio state before building")
  .option("--rojo", "Enable Rojo-compatible parsing")
  .option("--rojo-project <file>", "Use a Rojo project file")
  .action((_options, command: Command) =>
    runBuild(command.optsWithGlobals<BuildOptions>()),
  );

program
  .command("push")
  .description("Mount local files or a folder into Studio at a specific path")
  .option(
    "-s, --source <path...>",
    "Scripts, folders or azul.package.json to push (a script brings its same-named sibling folder). Multiple sources need --destination and native mode.",
  )
  .option(
    "-d, --destination <path>",
    'Studio destination path (i.e "ReplicatedStorage.Packages")',
  )
  .addOption(sourcemapOption("Push from a sourcemap"))
  .option("--no-place-config", "Ignore push mappings from place ModuleScript")
  .option("--destructive", "Wipe destination children before pushing")
  .option("--rojo", "Enable Rojo-compatible parsing")
  .option("--rojo-project <file>", "Use a Rojo project file")
  .action(async (_options, command: Command) => {
    const options = command.optsWithGlobals<PushOptions>();
    try {
      await runPush(options, options.source ?? []);
    } catch (error) {
      command.error(error instanceof Error ? error.message : String(error));
    }
  });

program
  .command("pack")
  .description("Serialize Studio instance properties into a sourcemap")
  .option(
    "-o, --output <file>",
    "Sourcemap path to write (default: config.sourcemapPath)",
  )
  .option("--scripts-only", "Serialize only scripts and their descendants")
  .option(
    "--rojo",
    `Also generate a Rojo project (${ROJO_PROJECT_FILE_NAME}), rooted at the package root if there's a package file`,
  )
  .option("--rojo-output <file>", "Rojo project path to write (implies --rojo)")
  .action((_options, command: Command) =>
    runPack(command.optsWithGlobals<PackOptions>()),
  );

program
  .command("config")
  .description("Open the Azul config file in your default editor")
  .option("--path", "Print config file path")
  .action((options: { path?: boolean }) => runConfig(options.path));

program
  .command("open-studio")
  .description("Open Roblox Studio on the place ID recorded in the sourcemap")
  .addOption(sourcemapOption("Sourcemap to read the place ID from"))
  .option(
    "--place-id <number>",
    "Open this place ID instead of reading a sourcemap",
    parseNumberInRange(1, Number.MAX_SAFE_INTEGER),
  )
  .action((options: OpenStudioOptions) => runOpenStudio(options));

// Set after the subcommands so they don't inherit it; the root action reports unknown commands itself.
program.allowExcessArguments();

await program.parseAsync();

/** `--from-sourcemap` with an optional value; bare, it uses the configured sourcemap path. */
function sourcemapOption(description: string): Option {
  return new Option("--from-sourcemap [file]", description).preset(
    config.sourcemapPath,
  );
}

function parseNumberInRange(
  min: number,
  max: number,
): (value: string) => number {
  return (value) => {
    const numberValue = Number(value);
    if (isNaN(numberValue) || numberValue < min || numberValue > max) {
      throw new InvalidArgumentError(
        `Expected a number between ${min} and ${max}.`,
      );
    }
    return numberValue;
  };
}

async function runConfig(printPath = false): Promise<void> {
  const userConfigPath = getUserConfigPath();

  if (printPath) {
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

async function runOpenStudio(options: OpenStudioOptions): Promise<void> {
  const placeId = options.placeId ?? readPackedPlaceId(options.fromSourcemap);

  await openWithDefaultApp(
    `roblox-studio:1+task:EditPlace+placeId:${placeId}+universeId:0`,
  );
  log.info(`Opening Roblox Studio on place ${placeId}...`);

  process.exit(0);
}

/** Shared setup for commands that work on the local project. */
async function startProjectCommand(options: GlobalOptions): Promise<void> {
  const currentPath = process.cwd();
  if (
    (currentPath.includes(`\\${config.syncDir}`) ||
      currentPath.includes(`/${config.syncDir}`)) &&
    options.warn
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

  if (options.syncDir) config.syncDir = resolve(options.syncDir);
  if (options.port) config.port = options.port;
  if (options.debug) config.debugMode = true;

  log.debug(`Debug mode is on!`);
}

async function runBuild(options: BuildOptions): Promise<void> {
  await startProjectCommand(options);

  if (!options.rojo && hasUserRojoProject()) {
    log.warn(
      'Detected a Rojo project file! You can enable Rojo compatibility mode by passing the "--rojo" flag.',
    );
  }

  const hasBuildSpecificOptions =
    options.rojo ||
    Boolean(options.rojoProject) ||
    options.fromSourcemap !== undefined;
  // || options.destructive;
  // Don't consider passing "--destructive" as enough to bypass interactive mode,
  // since destructive building without a sourcemap is very likely a mistake.

  let applySourcemapProperties = true;
  let useSourcemapAsSource = options.fromSourcemap !== undefined;
  let interactiveDestructive = options.destructive;
  let interactiveSourcemapPath = options.fromSourcemap;

  if (!hasBuildSpecificOptions) {
    const chosenSourcemap = await promptSourcemapChoice("build");
    if (chosenSourcemap) {
      useSourcemapAsSource = true;
      interactiveSourcemapPath = chosenSourcemap;
      applySourcemapProperties = await prompt.getYesNoInput(
        `Apply packed properties/attributes from ${chosenSourcemap}?`,
        true,
      );
    } else {
      useSourcemapAsSource = false;
      applySourcemapProperties = false;
      log.info(
        "Not using sourcemap. Azul will recreate instances as scripts/folders based on your local filesystem structure with default properties/attributes.",
      );
    }

    // Only ask about destructive option if we're building from sourcemap.
    // Destructively building without a sourcemap is very likely a mistake, since it wipes everything in Studio instead of building "on top".
    // This functionality is still possible with the "--destructive" flag if someone really wants it
    if (useSourcemapAsSource) {
      interactiveDestructive = await prompt.getYesNoInput(
        "Destructive build (wipe everything in Studio & build from scratch)?",
      );
    }
  }

  if (options.warn) {
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
    rojoMode: options.rojo,
    rojoProjectFile: options.rojoProject ?? undefined,
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

async function runPush(options: PushOptions, sources: string[]): Promise<void> {
  const [source, ...additionalSources] = sources;
  await startProjectCommand(options);

  const usePlaceConfig = options.placeConfig;

  const hasPushSpecificOptions = Boolean(
    source ||
    options.destination ||
    options.destructive ||
    !usePlaceConfig ||
    options.rojo ||
    options.rojoProject ||
    options.fromSourcemap,
  );

  let interactiveSource: string | undefined = source;
  let interactiveDest = options.destination ?? undefined;
  let interactiveDestructive = options.destructive;
  let interactiveUsePlaceConfig = usePlaceConfig;
  let useSourcemapAsSource =
    !options.rojo && options.fromSourcemap !== undefined;
  let applySourcemapProperties =
    !options.rojo && options.fromSourcemap === undefined;
  let interactiveSourcemapPath = options.fromSourcemap;

  if (!hasPushSpecificOptions && !options.rojo) {
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
    !options.rojo &&
    interactiveUsePlaceConfig &&
    !(interactiveSource && interactiveDest);

  const isPackageSource = Boolean(
    interactiveSource &&
    (findPackageFile(interactiveSource) ||
      findChildPackageDirs(interactiveSource).length > 0),
  );

  if (
    !options.rojo &&
    options.fromSourcemap === undefined &&
    !willUsePlaceConfig &&
    !isPackageSource
  ) {
    const chosenSourcemap = await promptSourcemapChoice("push");
    if (chosenSourcemap) {
      useSourcemapAsSource = true;
      interactiveSourcemapPath = chosenSourcemap;
      applySourcemapProperties = await prompt.getYesNoInput(
        `Apply packed properties/attributes from ${chosenSourcemap}?`,
        true,
      );
    } else {
      useSourcemapAsSource = false;
      applySourcemapProperties = false;
      log.info(
        `Not using sourcemap. Azul will recreate instances as scripts/folders based on your local filesystem structure with default properties/attributes.`,
      );
    }
  }

  if (!options.rojo && hasUserRojoProject()) {
    log.info(
      "Detected a Rojo project file. Azul stays in native mode unless you pass --rojo.",
    );
  }

  // Checked before PushCommand starts the server, so Studio logs can't interrupt the prompt.
  if (interactiveDest) {
    if (/^game[./\\]/i.test(interactiveDest)) {
      log.warn(
        "Do not use 'game.' in the destination; it is implied. Stripping it.",
      );
      interactiveDest = interactiveDest.slice(5);
    }

    const checkedSegments = await confirmDestinationRoot(
      parseDestination(interactiveDest),
      options.warn,
    );
    interactiveDest = checkedSegments.join(".");
  }

  if (options.destructive && options.warn) {
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
    additionalSources,
    destination: interactiveDest ?? undefined,
    destructive: interactiveDestructive,
    usePlaceConfig: options.rojo ? false : interactiveUsePlaceConfig,
    rojoMode: options.rojo,
    rojoProjectFile: options.rojoProject ?? undefined,
    applySourcemapProperties,
    useSourcemapAsSource,
    sourcemapPath: interactiveSourcemapPath,
    warn: options.warn,
  }).run();

  log.info("Push command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  process.exit(0);
}

async function runPack(options: PackOptions): Promise<void> {
  await startProjectCommand(options);

  let scriptsOnly = options.scriptsOnly;
  let rojo = options.rojo || options.rojoOutput !== undefined;

  const hasPackSpecificOptions =
    options.output !== undefined || scriptsOnly || rojo;

  let finalOutputPath = options.output ?? config.sourcemapPath;
  let packageRoot: string | undefined;

  if (!hasPackSpecificOptions) {
    const interactive = await promptPackInteractive(config.sourcemapPath);
    finalOutputPath = interactive.outputPath;
    scriptsOnly = interactive.scriptsOnly;
    packageRoot = interactive.packageRoot;
    rojo = await prompt.getYesNoInput(
      `Generate a Rojo project? (writes ${ROJO_PROJECT_FILE_NAME})`,
      false,
    );
  }

  if (
    basename(finalOutputPath) === "sourcemap.json" ||
    resolve(finalOutputPath) === resolve(config.sourcemapPath)
  ) {
    log.warn(
      `Packing into ${finalOutputPath}. Consider giving packed sourcemaps their own name, like "game.sourcemap.json": https://azul.ransomwave.games/advanced/distributing-code/#best-practices`,
    );
  }

  let rojoProjectFile: string | null = null;
  if (rojo) {
    rojoProjectFile = resolve(options.rojoOutput ?? ROJO_PROJECT_FILE_NAME);

    if (!/\.project\.jsonc?$/.test(rojoProjectFile)) {
      log.error(
        `Rojo project files must end in ".project.json": ${options.rojoOutput}`,
      );
      process.exit(1);
    }

    if (!(await confirmRojoProjectOverwrite(rojoProjectFile, !options.warn))) {
      log.info("Skipping Rojo project generation.");
      rojoProjectFile = null;
    }
  }

  const packed = await new PackCommand({
    outputPath: finalOutputPath,
    scriptsAndDescendantsOnly: scriptsOnly,
  }).run();

  if (packed && packageRoot) {
    const packageFile = writePackageFile(
      process.cwd(),
      packageRoot,
      finalOutputPath,
    );
    log.success(`Wrote package file ${packageFile}`);
  }

  if (packed && rojoProjectFile) {
    generateRojoProject(rojoProjectFile, finalOutputPath);
  }

  log.info("Pack command completed.");
  process.exit(0);
}

async function runDaemon(options: GlobalOptions): Promise<void> {
  await startProjectCommand(options);

  const liveDaemon = new SyncDaemon();
  liveDaemon.start();

  let liveDaemonStopping = false;
  const stopLiveDaemon = async (signal: string): Promise<void> => {
    if (liveDaemonStopping) {
      log.warn("Exiting without waiting for shutdown to finish.");
      process.exit(1);
    }

    liveDaemonStopping = true;
    log.info(`Received ${signal}, shutting down...`);

    try {
      await liveDaemon.packOnExit();
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
}

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
 * Prompts the user to choose a sourcemap file from the current directory (or subdirectory) to use for building or pushing.
 */
async function promptSourcemapChoice(action: string): Promise<string | null> {
  const found = findSourcemaps();

  if (found.length === 0) {
    log.info(
      `No sourcemaps found in ${dirname(resolve(config.sourcemapPath))}.`,
    );
    return null;
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
  packageRoot?: string;
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

  const existingPackageFile = findPackageFile(process.cwd());
  if (existingPackageFile) {
    log.info(
      `Skipped package setup: found an existing package file at ./${relative(process.cwd(), existingPackageFile)}`,
    );
    return { outputPath, scriptsOnly };
  }

  if (
    !(await prompt.getYesNoInput(
      "Is this a package? (writes azul.package.json)",
      false,
    ))
  ) {
    return { outputPath, scriptsOnly };
  }

  const defaultRoot = `./${relative(
    process.cwd(),
    join(resolve(config.syncDir), "ReplicatedStorage"),
  )
    .split("\\")
    .join("/")}`;
  const packageRoot = (
    await prompt.getInput(
      "Package root? (the folder whose contents get pushed)",
      defaultRoot,
    )
  ).trim();

  if (resolve(packageRoot) === resolve(config.syncDir)) {
    log.warn(
      `Package root ${packageRoot} is the whole project, which can't be pushed. Point it at a folder inside a service instead.`,
    );
  } else if (!fs.existsSync(packageRoot)) {
    log.warn(`Package root ${packageRoot} does not exist yet.`);
  }

  return { outputPath, scriptsOnly, packageRoot };
}

/**
 * Whether the current folder's default project is a Rojo project the user
 * wrote, rather than one Azul generated for a package or place.
 */
function hasUserRojoProject(): boolean {
  const projectFile = findDefaultProjectFile(process.cwd());
  return (
    projectFile !== null &&
    !isGeneratedRojoProject(projectFile) &&
    !findPackageFile(process.cwd())
  );
}

/**
 * Asks before replacing a project file Azul didn't generate, unless --no-warn.
 */
async function confirmRojoProjectOverwrite(
  projectFile: string,
  noWarn: boolean,
): Promise<boolean> {
  if (
    noWarn ||
    !fs.existsSync(projectFile) ||
    isGeneratedRojoProject(projectFile)
  ) {
    return true;
  }

  const shown = relative(process.cwd(), projectFile) || projectFile;
  log.warn(`${shown} already exists and wasn't generated by Azul.`);
  return prompt.getYesNoInput(
    `Overwrite ${shown} with the generated Rojo project?`,
    false,
  );
}

/**
 * Writes a Rojo project from a packed sourcemap: a model project rooted at the
 * package root if the project has a package file, or else a place project.
 */
function generateRojoProject(projectFile: string, sourcemapPath: string): void {
  const shown = relative(process.cwd(), projectFile) || projectFile;

  try {
    const packageFile = findPackageFile(process.cwd());
    const pkg = packageFile ? loadPackageFile(packageFile) : null;
    const sourcemap = JSON.parse(fs.readFileSync(sourcemapPath, "utf8"));

    const project = buildRojoProject(sourcemap, {
      projectFile,
      baseDir: process.cwd(),
      syncDir: config.syncDir,
      name: pkg?.name ?? basename(process.cwd()),
      packageRoot: pkg?.root,
    });
    writeRojoProject(project, projectFile, resolve(sourcemapPath));

    log.success(
      `Wrote ${pkg ? "model" : "place"} Rojo project ${shown}${pkg ? ` (rooted at ${relative(process.cwd(), pkg.root)})` : ""}`,
    );

    const shadowing = findDefaultProjectFile(dirname(projectFile));
    if (
      shadowing &&
      shadowing !== projectFile &&
      basename(projectFile).startsWith("default.project.")
    ) {
      log.warn(
        `Rojo uses ${relative(process.cwd(), shadowing)} over ${shown}. Delete or rename it so the generated project is used.`,
      );
    }
  } catch (error) {
    log.error(`Failed to generate ${shown}: ${(error as Error).message}`);
  }
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
