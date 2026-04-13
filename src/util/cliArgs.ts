import { config } from "../config.js";
import { parseArgs } from "node:util";

export interface ParsedCliArgs {
  command: string | null;

  //   Global options
  help: boolean;
  version: boolean;
  debug: boolean;
  noWarn: boolean;
  syncDir?: string;
  port?: number;

  //   Build/Push options
  rojo: boolean;
  rojoProject?: string;
  fromSourcemap?: string;
  //   fromSourcemapValue: string | null;
  source?: string;
  destination?: string;
  noPlaceConfig: boolean;
  destructive: boolean;

  //   Pack options
  output?: string;
  scriptsOnly: boolean;

  //   Config options
  configPath: boolean;
}

export function parseCliArgs(argv: string[]): ParsedCliArgs {
  const args = ensureOptionalStringFlagValues(argv, ["--from-sourcemap"]);

  const { values, positionals } = parseArgs({
    args,
    strict: false,
    allowPositionals: true,
    options: {
      // Global options
      help: { type: "boolean", short: "h" },
      version: { type: "boolean" },
      debug: { type: "boolean" },
      "no-warn": { type: "boolean" },
      "sync-dir": { type: "string" },
      port: { type: "string" },

      // Build/Push options
      rojo: { type: "boolean" },
      "rojo-project": { type: "string" },
      "from-sourcemap": { type: "string" },
      source: { type: "string", short: "s" },
      destination: { type: "string", short: "d" },
      "no-place-config": { type: "boolean" },
      destructive: { type: "boolean" },

      // Pack options
      output: { type: "string", short: "o" },
      "scripts-only": { type: "boolean" },

      // Config options
      path: { type: "boolean" },
    },
  });

  const command = positionals[0] ?? null;
  //   const fromSourcemapRawValue = getStringOption(values, "from-sourcemap");

  return {
    command,
    help: getBooleanOption(values, "help"),
    version: getBooleanOption(values, "version"),
    debug: getBooleanOption(values, "debug"),
    noWarn: getBooleanOption(values, "no-warn"),
    configPath: getBooleanOption(values, "path"),
    syncDir: getStringOption(values, "sync-dir"),
    port: getNumberOptionInRange(values, "port", 1, 65535),
    rojo: getBooleanOption(values, "rojo"),
    rojoProject: getStringOption(values, "rojo-project"),
    fromSourcemap: getStringOptionWithImplicitDefault(
      values,
      "from-sourcemap",
      config.sourcemapPath,
    ),
    // fromSourcemap: fromSourcemapRawValue !== undefined,
    // fromSourcemapValue:
    //   fromSourcemapRawValue === "" || fromSourcemapRawValue === undefined
    //     ? null
    //     : fromSourcemapRawValue,
    source: getStringOption(values, "source"),
    destination: getStringOption(values, "destination"),
    noPlaceConfig: getBooleanOption(values, "no-place-config"),
    destructive: getBooleanOption(values, "destructive"),
    output: getStringOption(values, "output"),
    scriptsOnly: getBooleanOption(values, "scripts-only"),
  };
}

function getBooleanOption(
  values: Record<string, string | boolean | undefined>,
  flagName: string,
): boolean {
  return values[flagName] === true;
}

function getStringOption(
  values: Record<string, string | boolean | undefined>,
  flagName: string,
  //   hasOptionalValue = false, // For flags that can be provided as --flag or --flag=value
): string | undefined {
  const flagValue = values[flagName];

  return typeof flagValue === "string" ? flagValue : undefined;
}

function getStringOptionWithImplicitDefault(
  values: Record<string, string | boolean | undefined>,
  flagName: string,
  defaultValue: string,
): string | undefined {
  const flagValue = values[flagName];

  if (flagValue === undefined) {
    return undefined;
  }

  if (flagValue === "") {
    return defaultValue;
  }

  return typeof flagValue === "string" ? flagValue : undefined;
}

function getNumberOptionInRange(
  values: Record<string, string | boolean | undefined>,
  flagName: string,
  min: number,
  max: number,
): undefined | number {
  const value = getStringOption(values, flagName);

  if (value === undefined) {
    return undefined;
  }

  const numberValue = Number(value);
  if (isNaN(numberValue) || numberValue < min || numberValue > max) {
    throw new Error(
      `Invalid --${flagName} value "${value}": expected a number between ${min} and ${max}.`,
    );
  }

  return numberValue;
}

function ensureOptionalStringFlagValues(
  argv: string[],
  flags: string[],
): string[] {
  const normalized: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const matchedFlag = flags.find((flag) => arg === flag);

    if (!matchedFlag) {
      normalized.push(arg);
      continue;
    }

    const nextArg = argv[i + 1];
    if (!nextArg || nextArg.startsWith("-")) {
      normalized.push(`${matchedFlag}=`);
      continue;
    }

    normalized.push(arg);
  }

  return normalized;
}
