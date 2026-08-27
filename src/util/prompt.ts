import { confirm, input } from "@inquirer/prompts";
import { log, promptPrefix } from "./log.js";

/**
 * Inquirer needs raw-mode stdin. Without a TTY (CI, piped input) it aborts with
 * a bare ExitPromptError, so fail early with something actionable instead.
 */
function assertInteractive(): void {
  if (!process.stdin.isTTY) {
    throw new Error(
      "Azul needs an interactive terminal to ask this, but stdin is not a TTY. Pass the relevant flags (--no-warn, --destructive, -s/-d, -o, --scripts-only) to run non-interactively.",
    );
  }
}

/** Ctrl+C inside a prompt throws instead of killing the process. Exit quietly. */
async function ask<T>(run: () => Promise<T>): Promise<T> {
  assertInteractive();

  try {
    return await run();
  } catch (error) {
    if (error instanceof Error && error.name === "ExitPromptError") {
      log.info("Cancelled.");
      process.exit(130);
    }
    throw error;
  }
}

// Keeps prompts visually in line with the rest of the logger output.
const theme = () => ({ prefix: promptPrefix() });

export const prompt = {
  getInput(message: string, defaultValue?: string): Promise<string> {
    return ask(() => input({ message, default: defaultValue, theme: theme() }));
  },

  getYesNoInput(message: string, defaultValue = false): Promise<boolean> {
    return ask(() =>
      confirm({ message, default: defaultValue, theme: theme() }),
    );
  },
};
