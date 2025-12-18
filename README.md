# <span><img src="./docs/assets/logo.png" alt="Azul Logo" height="30"></span> Azul

Azul is a two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support, which allows code completion & type checking.

Azul allows you to use professional-grade tools like Visual Studio Code in Roblox development.

_Yes, the name is a pun on Rojo (Spanish for "red"). Azul means "blue"!_

<a href="#quick-start"><b>Quick Start</b></a> — <a href="#why-azul"><b>Why Azul</b></a> — <a href="#configuration"><b>Configuration</b></a>

## Philosophy

Unlike Rojo, Azul treats **Studio as the source of truth.** The local filesystem mirrors what's in Studio, not the other way around.

When you do need to seed Studio from local files, run the one-time `azul build` command; after that, the regular sync loop continues to treat Studio as primary.

## Features

- - [x] 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- - [x] 🏗️ **[Build command](#build-command)**: `azul build` one-time pushes your local files into Studio (creates or overwrites, never deletes)
- - [x] 🌳 **DataModel mirroring**: Instance hierarchy 1:1 mapped to folder structure
- - [x] 🎯 **No manual config / required structure**: Works out of the box with new and existing Roblox Studio projects, regardless of structure.
- - [x] 🗺️ **Automatic sourcemap generation**: Generates a Rojo-compatible `sourcemap.json` so tools like Luau-lsp work out of the box.

### Planned features

- - [ ] 📦 **Package Manager Integration**: Allow seamless sync of packages installed via package managers (i.e Wally).

## Why Azul?

Because Azul is as simple as it gets: Run the azul command in your project folder, connect the companion plugin in Studio & start coding.

Compatible with projects both old and new, no more extra worrying about how to “Rojo-ify” your project. Your code is literally 1:1 mapped to what’s in Studio.

### Rojo already exists, why make another tool?

I created Azul because I wanted a way to use my favorite IDE in Roblox development without the hassle of setting up Rojo projects, managing configurations, and being forced to commit to a filesystem-only workflow.

Rojo is a great tool for many developers, but it often requires a significant investment in setup and maintenance that drives many away from using local development tools altogether. Azul aims to simplify this process, allowing you to focus on coding rather than tooling.

### Why not use the upcoming Script Sync feature?

Azul offers several advantages over the upcoming Script Sync feature:

- **Azul mirrors everything**: Script Sync can only sync specified folders and scripts, not entire projects. Azul directly mirrors the entire DataModel, meaning you don't have to worry about manually syncing specific parts of your project.

- **Building from filesystem**: Script Sync only syncs changes made in Studio to the filesystem. Azul allows you to push changes from your local files into Studio using the `azul build` command.

- **Generates a Rojo-compatible `sourcemap.json`**: This allows any tooling that require Rojo-style sourcemaps _(like luau-lsp, the language server)_ to work seamlessly.

- **You can use it today!**: Azul requires no commitment to a specific project structure. If you want to try out Script Sync (or any other tool) in the future, Azul won't get in your way.

---

## Quick Start

### Auto-Install (Recommended)

> **For MacOS users: `install-linux.sh` should also work for you.** It will attempt to use the `brew` command (install [Homebrew](https://brew.sh/) if you don't have it) to install Node.js.
>
> Alternatively, you can install Node.js manually from [nodejs.org](https://nodejs.org/).

1. Clone this repository or [download it as a ZIP](https://github.com/Ransomwave/azul/archive/refs/heads/main.zip) and extract it.
2. Inside the extracted folder, locate the `/scripts` Folder
3. Run the install script for your OS (`install-windows.ps1`, `install-linux.sh`).
4. Install the Azul Companion Plugin to Roblox Studio.
   - **Guide: [Azul Plugin: Install Instructions](/plugin/README.md)**
5. Create a new Folder for your Azul project and open it in VSCode.
   - It is recommended to create a new empty folder to avoid conflicts with existing files.
6. With the terminal open in your project folder, run `azul` to start.
7. In Roblox Studio, click on the Azul icon in the toolbar to toggle syncing.
8. Start coding!
9. (Optional) [Set up VSCode with Luau-LSP](#recommended-use-vscode-with-luau-lsp) for the best experience.

### Manual Install

1. Clone the repository or download the ZIP and extract it.
2. Install Node.js from [nodejs.org](https://nodejs.org/) or by using your system's package manager:
   ```bash
   # Windows (using winget)
   winget install OpenJS.NodeJS.LTS
   # macOS (using Homebrew)
   brew install node
   # Linux (using apt)
   sudo apt install nodejs npm
   ```
3. Install dependencies by running
   ```
   npm install
   ```
4. Build the project
   ```
   npm run build
   ```
5. Install the project globally
   ```
   npm install -g .
   ```
6. Install the Azul Companion Plugin to Roblox Studio.
   - **Guide: [Azul Plugin: Install Instructions](/plugin/README.md)**
7. Create a new Folder for your Azul project and open it in VSCode.
   - It is recommended to create a new empty folder to avoid conflicts with existing files.
8. With the terminal open in your project folder, run `azul` to start.
9. In Roblox Studio, click on the Azul icon in the toolbar to toggle syncing.
10. Start coding!

### Recommended: Use VSCode with Luau-LSP

To get the best experience, use [Visual Studio Code](https://code.visualstudio.com/) with the [Luau Language Server extension](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp).

To get IntelliSense working, open your `User Settings (JSON)` from the command palette (`Ctrl+Shift+P` or `Cmd+Shift+P`) and make sure to set up luau-lsp like this:

```json
  "luau-lsp.plugin.enabled": true,
  "luau-lsp.sourcemap.enabled": true,
  "luau-lsp.sourcemap.autogenerate": false,
  "luau-lsp.sourcemap.sourcemapFile": "sourcemap.json",
  "luau-lsp.sourcemap.includeNonScripts": true,
  "luau-lsp.sourcemap.useVSCodeWatcher": true,
```

This is my recommended setup for Azul projects. That said, Azul is compatible with any IDE or text editor that can edit `.luau` files. Luau-LSP is also available for other editors like [Neovim](https://github.com/lopi-py/luau-lsp.nvim).

## How It Works

### Desktop Daemon (TypeScript)

- Maintains virtual tree of Studio's DataModel
- Converts instances to filesystem structure
- Watches local files for changes
- Generates Rojo-compatible sourcemap.json
- Build mode scans your sync directory and sends a snapshot to Studio (create/overwrite only: no deletes)

### Studio Plugin (Luau)

- Assigns stable GUIDs to instances
- Detects script changes, renames, moves, deletions
- Sends updates to daemon via WebSocket
- Applies incoming patches from file edits

## Filesystem Mapping

### Simple Scripts

An example of a single server Script instance:

- Roblox: `ReplicatedStorage.Modules.MyServerScript`
- Filesystem: `sync\ReplicatedStorage\Modules\MyServerScript.server.luau`

### Nested Scripts

Nested instances are represented as a new folder besides the parent Script. For example, a Script nested inside another Script:

- Roblox: `ServerScriptService.Game.ParentScript.NestedScript`
- Filesystem:
  - `sync\ServerScriptService\Game\ParentScript.server.luau`
  - `sync\ServerScriptService\Game\ParentScript\NestedScript.server.luau`

### Script Types

Script types are indicated by suffixes:

- `.server.luau` for `Script`
- `.client.luau` for `LocalScript`
- `.module.luau` for `ModuleScript`
- No suffix defaults to `ModuleScript`

## Build Command

Importing code from elsewhere that isn't Roblox? Need to create a easily-reusable base project? The `azul build` command has you covered.

- **What it does:** Pushes your sync directory into Studio once, creating missing folders/scripts and overwriting matching scripts. Unrelated Studio instances are left untouched.
- **When to use:** Bootstrapping a new project, restoring from version control, importing files from non-roblox sources or reseeding a clean Studio place before normal two-way sync.
- **How to run:** Run `azul build` in your project folder with the terminal. Run the Companion Plugin and see the changes appear in Studio!

## Configuration

Edit `src/config.ts` to customize:

- **`port`**: Port used for communication between the Desktop Daemon and Studio Plugin.
- **`syncDir`**: Directory where the DataModel will be mirrored.
- **`sourcemapPath`**: Path to the generated `sourcemap.json` file.
- **`scriptExtension`**: (`.lua` vs `.luau`)
- **`deleteOrphansOnConnect`**: Whether to delete unmapped files in the sync directory after a new connection/full snapshot. These files are those that don't correspond to any instance in the DataModel. They could be leftovers from previous syncs or files created manually in the sync directory.
- **`debugMode`**: Enable or disable debug logging.

The plugin's settings can be edited from the GUI or by editing `src/plugin/AzulSync.lua`:

- **`WS_URL`**: Port used for communication between the Desktop Daemon and Studio Plugin.
- **`GUID_ATTRIBUTE`**: Name of the attribute used to store GUIDs.
- **`SERVICE_LIST`**: A list of services. This list can act as a whitelist (only these services are synced) or a blacklist (these services are excluded from syncing).
  - **`LIST_TYPE`**: Whether the service list is treated as a whitelist or blacklist.
- **`EXCLUDED_PARENTS`**: Parents to exclude from syncing _(i.e. `ServerStorage.RecPlugins`, a Folder managed by an external plugin you don't want to sync)_.
- **`DEBUG_MODE`**: Enable or disable debug logging.
- **`SILENT_MODE`**: Suppress all Plugin print statements except for errors.

## Contributing

Contributions are welcome! Please open issues or pull requests on GitHub. I want to make Azul the best it can be for myself and anybody who wants to use it.
