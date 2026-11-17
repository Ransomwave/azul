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
    const takesNextArg = flag === "-s" || flag === "--source";
    let cursor = flagIndex + 1;
    const finalParsed = [
      takesNextArg ? argv[cursor++] : flag.replace(/^(-s|--source=)/, ""),
    ];
    const finalOperands: string[] = [];
    // Commander consumes following values only for the unattached variadic flag.
    const following = takesNextArg ? finalParsed : finalOperands;
    while (
      cursor < end &&
      (argv[cursor] === "-" || !argv[cursor].startsWith("-"))
    ) {
      following.push(argv[cursor++]);
    }
    if (cursor === terminator) finalOperands.push(...argv.slice(terminator + 1));
    const parsedSuffix = parsed.slice(-finalParsed.length);
    if (
      parsedSuffix.length === finalParsed.length &&
      parsedSuffix.every((source, i) => source === finalParsed[i]) &&
      operands.length === finalOperands.length &&
      operands.every((source, i) => source === finalOperands[i])
    ) {
      return [...parsed, ...operands];
    }
  }

  throw new Error(
    "Additional push sources must follow --source without an intervening option.",
  );
}
