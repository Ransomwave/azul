/**
 * Simple logging utility with color support
 */

const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  dim: "\x1b[2m",

  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  white: "\x1b[37m",
};

function timestamp(): string {
  return new Date().toISOString().slice(11, 23);
}

export const log = {
  info(message: string, ...args: any[]): void {
    console.log(
      `${colors.dim}[${timestamp()}]${colors.reset} ${colors.blue}ℹ${
        colors.reset
      } ${message}`,
      ...args
    );
  },

  success(message: string, ...args: any[]): void {
    console.log(
      `${colors.dim}[${timestamp()}]${colors.reset} ${colors.green}✓${
        colors.reset
      } ${message}`,
      ...args
    );
  },

  warn(message: string, ...args: any[]): void {
    console.log(
      `${colors.dim}[${timestamp()}]${colors.reset} ${colors.yellow}⚠${
        colors.reset
      } ${message}`,
      ...args
    );
  },

  error(message: string, ...args: any[]): void {
    console.error(
      `${colors.dim}[${timestamp()}]${colors.reset} ${colors.red}✗${
        colors.reset
      } ${message}`,
      ...args
    );
  },

  debug(message: string, ...args: any[]): void {
    if (process.env.DEBUG) {
      console.log(
        `${colors.dim}[${timestamp()}] 🔍 ${message}${colors.reset}`,
        ...args
      );
    }
  },

  script(path: string, action: "created" | "updated" | "deleted"): void {
    const emoji = action === "created" ? "+" : action === "updated" ? "~" : "−";
    const color =
      action === "created"
        ? colors.green
        : action === "updated"
        ? colors.yellow
        : colors.red;
    console.log(
      `${colors.dim}[${timestamp()}]${colors.reset} ${color}${emoji}${
        colors.reset
      } ${path}`
    );
  },
};
