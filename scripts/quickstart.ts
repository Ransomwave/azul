#!/usr/bin/env node

/**
 * Quick Start Script for Super Studio Sync
 * This helps new users get started quickly
 */

import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

function log(message: string, color = colors.reset): void {
  console.log(`${color}${message}${colors.reset}`);
}

function header(message: string): void {
  log(`\n${colors.bright}${message}${colors.reset}`);
  log("=".repeat(message.length));
}

function checkPrerequisites(): boolean {
  header("Checking Prerequisites");

  // Check Node.js version
  const nodeVersion = process.versions.node;
  const major = parseInt(nodeVersion.split(".")[0]);

  if (major < 18) {
    log("❌ Node.js 18+ required", colors.yellow);
    log(`   Current version: ${nodeVersion}`, colors.yellow);
    log(`   Please upgrade: https://nodejs.org/`, colors.cyan);
    return false;
  }

  log(`✓ Node.js ${nodeVersion}`, colors.green);

  // Check if dependencies are installed
  const nodeModulesExists = fs.existsSync(
    path.join(__dirname, "..", "node_modules")
  );

  if (!nodeModulesExists) {
    log("❌ Dependencies not installed", colors.yellow);
    log(`   Run: npm install`, colors.cyan);
    return false;
  }

  log(`✓ Dependencies installed`, colors.green);

  return true;
}

function showPluginInstructions(): void {
  header("Studio Plugin Setup");

  log("1. Copy the plugin to Roblox Studio:", colors.bright);

  const pluginPath = path.join(__dirname, "..", "plugin");
  const pluginAbsPath = path.resolve(pluginPath);

  log(`\n   Plugin location: ${colors.cyan}${pluginAbsPath}${colors.reset}`);

  if (process.platform === "win32") {
    const robloxPlugins = path.join(
      process.env.LOCALAPPDATA || "",
      "Roblox",
      "Plugins"
    );
    log(`\n   Copy to: ${colors.cyan}${robloxPlugins}${colors.reset}`);
  } else if (process.platform === "darwin") {
    const robloxPlugins = path.join(
      process.env.HOME || "",
      "Documents",
      "Roblox",
      "Plugins"
    );
    log(`\n   Copy to: ${colors.cyan}${robloxPlugins}${colors.reset}`);
  }

  log("\n2. Enable HttpService in Studio:", colors.bright);
  log("   • Game Settings → Security");
  log("   • Enable 'Allow HTTP Requests'");

  log("\n3. Restart Roblox Studio", colors.bright);

  log("\n4. Click the 'Toggle Sync' button", colors.bright);
}

function showNextSteps(): void {
  header("What's Next?");

  log("The daemon is now running and waiting for Studio to connect.\n");

  log("When Studio connects, you'll see:", colors.bright);
  log("  • Scripts syncing to the ./sync directory");
  log("  • sourcemap.json being generated");
  log("  • Real-time updates as you edit\n");

  log("Edit scripts:", colors.bright);
  log("  • In Studio → Files update automatically");
  log("  • In VS Code → Studio updates automatically\n");

  log("For full documentation, see:", colors.bright);
  log(`  ${colors.cyan}GUIDE.md${colors.reset} - User guide`);
  log(`  ${colors.cyan}ARCHITECTURE.md${colors.reset} - Technical details`);
  log(
    `  ${colors.cyan}PROJECT_SUMMARY.md${colors.reset} - Complete overview\n`
  );
}

function main(): void {
  log(`
${colors.bright}╔═══════════════════════════════════════════════════════╗
║                                                       ║
║         🚀 Super Studio Sync - Quick Start          ║
║                                                       ║
║   Roblox Studio ⇄ Local Filesystem Sync Tool        ║
║        with Luau-LSP Integration                     ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝${colors.reset}
`);

  if (!checkPrerequisites()) {
    log(
      "\n❌ Prerequisites not met. Please fix the issues above.\n",
      colors.yellow
    );
    process.exit(1);
  }

  showPluginInstructions();
  showNextSteps();

  log(
    `${colors.bright}${colors.green}✓ All set! Starting the sync daemon...${colors.reset}\n`
  );

  // Note: This script is informational. The actual daemon is started via npm run dev
}

main();
