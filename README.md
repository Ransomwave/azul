# <span><img src="logo.png" alt="Azul Logo" height="30"></span> Azul

Azul is a two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support, which allows code completion & type checking.

Azul allows you to use professional-grade tools like Visual Studio Code in Roblox development.

Yes, the name is a pun on "Rojo" (Azul is Spanish for "blue").

<a href="#quick-start"><b>Quick Start</b></a> — <a href="#why-azul"><b>Why Azul</b></a> — <a href="#configuration"><b>Configuration</b></a>

## Philosophy

Unlike Rojo, Azul treats **Studio as the source of truth.** The local filesystem mirrors what's in Studio, not the other way around.

## Features

- - [x] 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- - [x] 🗺️ **Automatic sourcemap generation**: Rojo-compatible sourcemap.json for luau-lsp
- - [x] 🌳 **DataModel mirroring**: Instance hierarchy mapped to folder structure
- - [x] 🔌 **Real-time WebSocket communication**: Instant synchronization
- - [x] 🎯 **No manual configuration**: Works out of the box with new and existing projects.

### Planned features

- - [ ] 🍳 **Easy Plugin Configuration:** Interface for configuring the Studio Plugin.
- - [ ] 🏗️ **Build command:** `azul build` command to build from local files _(one-time filesystem -> Studio push)_
- - [ ] 📦 **Package Manager Integration**: Allow seamless sync of packages installed via package managers (i.e Wally).

## Why Azul?

Because Azul is as simple as it gets: you just want to edit your code in VSCode? Here you go. Projects new and old, big and small, it doesn't matter. Your code is 1:1 mapped to what's in Studio.

### Rojo already exists, why make another tool?

I created Azul because I don't agree with the opinion that the filesystem should be the source of truth for Roblox development. Considering Roblox's project structure, Studio provides the best representation of a game's state. Attempting to reverse this relationship often leads to a very frustrating experience.

I won't deny that Rojo is a great tool for many power users, but for me, it often felt like fighting against the natural workflow of Roblox development.

### Why not use the upcoming Script Sync feature?

I believe Script Sync is a great step forward from Roblox but, in the way it has been described, Azul offers several advantages:

- **Script Sync does not mirror the entire DataModel structure**: It only mirrors selected folders or Scripts, not the whole DataModel (Explorer).
- **Generates a Rojo-compatible `sourcemap.json`**: This allows any tooling that require Rojo-style sourcemaps _(like luau-lsp)_ to work seamlessly.
- **You can use it today!**: Unlike Rojo, Azul requires no commitment to a specific project structure. If want to try out Script Sync in the future, you can do so without any worries.

---

## Quick Start

### Auto-Install (Recommended)

> [!NOTE]
> Note that the following method is only available for Windows. If you are running macOS or Linux, please follow the [manual installation](#manual-installation).

1. [Download the repository as a ZIP](https://github.com/Ransomwave/azul/archive/refs/heads/main.zip) and extract it.
2. Run the `install-windows.ps1` script to Install Azul.
3. [Install the Azul Companion Plugin](/plugin/README.md) to Roblox Studio.
4. Create a new Folder for your Azul project and open it in VSCode.
   - It is recommended to create a new empty folder to avoid conflicts with existing files.
5. In the terminal, run `azul` to start.
6. In Roblox Studio, click on the Azul icon in the toolbar to toggle syncing.
7. Start coding!

### Manual Install

1. Clone the repository or download the ZIP and extract it.
2. Install Node.js (if you haven't already) from [nodejs.org](https://nodejs.org/) or by using winget:
   ```powershell
   winget install OpenJS.NodeJS.LTS
   ```
3. Install dependencies by running `npm install`.
4. Build the project with `npm run build`.
5. Install the project globally by running `npm install -g` in the project directory.
6. [Install the Azul Companion Plugin](/plugin/README.md) to Roblox Studio.
7. Create a new Folder for your Azul project and open it in VSCode.
   - It is recommended to create a new empty folder to avoid conflicts with existing files.
8. In the terminal, run `azul` to start.
9. In Roblox Studio, click on the Azul icon in the toolbar to toggle syncing.
10. Start coding!

## How It Works

### Desktop Daemon (TypeScript)

- Maintains virtual tree of Studio's DataModel
- Converts instances to filesystem structure
- Watches local files for changes
- Generates Rojo-compatible sourcemap.json

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

> [!WARNING]
> It is heavily advised to avoid nesting Scripts inside other Scripts due to potential confusion and complexity.

### Script Types

Script types are indicated by suffixes:

- `.server.luau` for `Script`
- `.client.luau` for `LocalScript`
- `.module.luau` for `ModuleScript`

## Configuration

Edit `src/config.ts` to customize:

- **`port`**: Port used for communication between the Desktop Daemon and Studio Plugin.
- **`syncDir`**: Directory where the DataModel will be mirrored.
- **`sourcemapPath`**: Path to the generated `sourcemap.json` file.
- **`scriptExtension`**: (`.lua` vs `.luau`)
- **`deleteOrphansOnConnect`**: Whether to delete unmapped files in the sync directory after a new connection/full snapshot. These files are those that don't correspond to any instance in the DataModel. They could be leftovers from previous syncs or files created manually in the sync directory.
- **`debugMode`**: Enable or disable debug logging.

Edit `src/plugin/AzulSync.lua` to customize:

- **`WS_URL`**: Port used for communication between the Desktop Daemon and Studio Plugin.
- **`GUID_ATTRIBUTE`**: Name of the attribute used to store GUIDs.
- **`SERVICE_LIST`**: A list of services. This list can act as a whitelist (only these services are synced) or a blacklist (these services are excluded from syncing).
  - **`LIST_TYPE`**: Whether the service list is treated as a whitelist or blacklist.
- **`EXCLUDED_PARENTS`**: Parents to exclude from syncing _(i.e. `ServerStorage.RecPlugins`, a Folder managed by an external plugin you don't want to sync)_.
- **`DEBUG_MODE`**: Enable or disable debug logging.
- **`SILENT_MODE`**: Suppress all Plugin print statements except for errors.

## Contributing

Contributions are welcome! Please open issues or pull requests on GitHub. I want to make Azul the best it can be for myself and anybody who wants to use it.
