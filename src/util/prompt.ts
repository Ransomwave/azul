import * as ReadLine from "readline";
import { log } from "./log.js";

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

export const prompt = {
  getInput(message: string): Promise<string> {
    log.userInput(message);
    return promptLine();
  },

  async getYesNoInput(
    message?: string,
    retryMessage?: string,
  ): Promise<boolean> {
    if (message) {
      log.userInput(message);
    }

    while (true) {
      const input = (await promptLine()).trim().toLowerCase();
      if (input === "y" || input === "yes") {
        return true;
      }
      if (input === "n" || input === "no") {
        return false;
      }
      log.userInput(retryMessage ?? "Please answer Y (yes) or N (no).");
    }
  },
};
