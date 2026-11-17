import { InvalidArgumentError } from "commander";

export function appendPushSource(source: string, previous: string[] = []): string[] {
  if (source === "") {
    throw new InvalidArgumentError("Source path must not be empty.");
  }
  return [...previous, source];
}

/**
 * Commander leaves operands after an attached option value or `--` outside
 * its variadic option. Accept them only when they form one source group.
 */
export function collectPushSources(
  parsed: string[],
  operands: string[],
  argv: string[],
): string[] {
  if (operands.length === 0) return parsed;
  if (operands.includes("")) throw new Error("Source path must not be empty.");

  const terminator = argv.indexOf("--");
  const end = terminator < 0 ? argv.length : terminator;
  let flagIndex = end - 1;
  while (
    flagIndex >= 0 &&
    !argv[flagIndex].startsWith("-s") &&
    argv[flagIndex] !== "--source" &&
    !argv[flagIndex].startsWith("--source=")
  ) {
    flagIndex--;
  }

  if (parsed.length > 0 && flagIndex >= 0) {
    const flag = argv[flagIndex];
    let cursor = flagIndex + 1;
    const first =
      flag === "-s" || flag === "--source"
        ? argv[cursor++]
        : flag.replace(/^(-s|--source=)/, "");
    const contiguous = [first];
    while (
      cursor < end &&
      (argv[cursor] === "-" || !argv[cursor].startsWith("-"))
    ) {
      contiguous.push(argv[cursor++]);
    }
    if (cursor === terminator) contiguous.push(...argv.slice(terminator + 1));
    const sources = [...parsed, ...operands];
    if (
      sources.length === contiguous.length &&
      sources.every((source, i) => source === contiguous[i])
    ) {
      return sources;
    }
  }

  throw new Error(
    "Additional push sources must follow --source without an intervening option.",
  );
}
