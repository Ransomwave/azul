import { log } from "./log.js";
import { prompt } from "./prompt.js";

/** Services people commonly use.
 * Not exhaustive!
 * If you're pushing to anything other than this, you probably know what you're doing. */
export const COMMON_SERVICES: readonly string[] = [
  "Workspace",
  "Players",
  "Lighting",
  "MaterialService",
  "ReplicatedFirst",
  "ReplicatedStorage",
  "ServerScriptService",
  "ServerStorage",
  "StarterGui",
  "StarterPack",
  "StarterPlayer",
  "Teams",
  "SoundService",
  "TextChatService",
  "Chat",
  "LocalizationService",
  "TestService",
];

const MAX_EDIT_DISTANCE = 2;
const CHARACTERS_PER_ALLOWED_EDIT = 4;

export type ServiceNameMatch =
  | { kind: "exact" }
  | { kind: "caseMismatch"; service: string }
  | { kind: "suggestion"; service: string }
  | { kind: "unknown" };

/**
 * Optimal string alignment distance: Levenshtein plus adjacent swaps
 * counted as one edit, so `Wokrspace` is 1 away from `Workspace`.
 */
export function editDistance(source: string, target: string): number {
  const distances: number[][] = [];
  for (let row = 0; row <= source.length; row++) {
    distances.push([row]);
  }
  for (let column = 1; column <= target.length; column++) {
    distances[0][column] = column;
  }

  for (let row = 1; row <= source.length; row++) {
    for (let column = 1; column <= target.length; column++) {
      const substitutionCost = source[row - 1] === target[column - 1] ? 0 : 1;
      let best = Math.min(
        distances[row - 1][column] + 1,
        distances[row][column - 1] + 1,
        distances[row - 1][column - 1] + substitutionCost,
      );

      const isAdjacentSwap =
        row > 1 &&
        column > 1 &&
        source[row - 1] === target[column - 2] &&
        source[row - 2] === target[column - 1];
      if (isAdjacentSwap) {
        best = Math.min(best, distances[row - 2][column - 2] + 1);
      }

      distances[row][column] = best;
    }
  }

  return distances[source.length][target.length];
}

/** Short names get fewer allowed edits so `Foo` doesn't match anything. */
function allowedEdits(name: string): number {
  return Math.min(
    MAX_EDIT_DISTANCE,
    Math.floor(name.length / CHARACTERS_PER_ALLOWED_EDIT),
  );
}

/** Classifies a destination's first segment against {@link COMMON_SERVICES}. */
export function matchServiceName(name: string): ServiceNameMatch {
  if (COMMON_SERVICES.includes(name)) {
    return { kind: "exact" };
  }

  const lowerName = name.toLowerCase();
  const caseInsensitiveMatch = COMMON_SERVICES.find(
    (service) => service.toLowerCase() === lowerName,
  );
  if (caseInsensitiveMatch) {
    return { kind: "caseMismatch", service: caseInsensitiveMatch };
  }

  let closestService: string | undefined;
  let closestDistance = allowedEdits(name) + 1;
  for (const service of COMMON_SERVICES) {
    const distance = editDistance(lowerName, service.toLowerCase());
    if (distance < closestDistance) {
      closestService = service;
      closestDistance = distance;
    }
  }

  return closestService
    ? { kind: "suggestion", service: closestService }
    : { kind: "unknown" };
}

/**
 * Checks the destination's first segment against common service names, since
 * an unknown root becomes a Folder directly under `game`. Fixes wrong case,
 * and asks about likely misspellings and unknown names unless `--no-warn`.
 * @param warn Whether to prompt (false under `--no-warn`).
 * @returns The segments to push to, with the root possibly corrected.
 */
export async function confirmDestinationRoot(
  segments: string[],
  warn: boolean,
): Promise<string[]> {
  const [root, ...rest] = segments;
  if (!root) return segments;

  const match = matchServiceName(root);
  if (match.kind === "exact") return segments;

  if (match.kind === "caseMismatch") {
    log.warn(`Correcting destination "${root}" to "${match.service}".`);
    return [match.service, ...rest];
  }

  if (match.kind === "suggestion") {
    if (!warn) {
      log.warn(
        `Destination "${root}" looks like a misspelling of "${match.service}". Pushing as typed.`,
      );
      return segments;
    }

    const choice = await prompt.getChoice(
      `Destination "${root}" isn't a known service. Did you mean "${match.service}"?`,
      [
        { name: `Use "${match.service}"`, value: "suggestion" },
        { name: `Keep "${root}"`, value: "keep" },
        { name: "Cancel", value: "cancel" },
      ] as const,
    );
    if (choice === "suggestion") return [match.service, ...rest];
    if (choice === "keep") return segments;
    exitCancelled();
  }

  const unknownMessage = `Destination "${root}" isn't a known common service and might be a mistake.`;
  if (!warn) {
    log.warn(unknownMessage);
    return segments;
  }

  const shouldContinue = await prompt.getYesNoInput(
    `${unknownMessage} Continue anyway?`,
  );
  if (!shouldContinue) exitCancelled();
  return segments;
}

function exitCancelled(): never {
  log.info("Exiting push command...");
  process.exit(0);
}
