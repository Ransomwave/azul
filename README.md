# <span><img src="logo.png" alt="Azul Logo" height="30"></span> Azul

Azul is a two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support, which allows code completion & type checking.

Azul allows you to use professional-grade tools like Visual Studio Code in Roblox development.

Yes, the name is a pun on "Rojo" (Azul is Spanish for "blue")!

<a href="#quick-start"><b>Quick Start</b></a> — <a href="#why-azul"><b>Why Azul</b></a> — <a href="#configuration"><b>Configuration</b></a>

## Philosophy

Unlike in Rojo, Azul treats **Studio as the source of truth.** The local filesystem mirrors what's in Studio, not the other way around.

## Features

- 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- 🗺️ **Automatic sourcemap generation**: Rojo-compatible sourcemap.json for luau-lsp
- 🌳 **DataModel mirroring**: Instance hierarchy mapped to folder structure
- 🔌 **Real-time WebSocket communication**: Instant synchronization
- 🎯 **No manual configuration**: Works out of the box with new and existing projects.

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

## Quick Start

### 1. Installation

Install all dependencies:

```bash
npm i
```

Install the Studio plugin:

- Copy the `plugin/` folder contents to your Roblox Studio plugins directory.

### 2. Run the sync daemon

```bash
npm run dev
```

### 3. Connect from Studio

Click on the Azul icon in the Studio toolbar to toggle syncing.

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

- Roblox: `ReplicatedStorage.Modules.PlaceholderScript`
- Filesystem: `sync\ReplicatedStorage\Modules\PlaceholderScript\init.luau`

## Sourcemap Integration

The generated `sourcemap.json` enables luau-lsp to provide:

- ✅ Module return type inference
- ✅ Instance hierarchy autocomplete
- ✅ Symbol cross-referencing
- ✅ Full DataModel awareness

## Configuration

Edit `src/config.ts` to customize:

- WebSocket port
- Sync directory
- File extensions (`.lua` vs `.luau`)
- Excluded services

Edit `src/plugin/AzulSync.lua` to customize:

- WebSocket port
- Excluded services
- Excluded parents

P.S. In the future, I may add a GUI for configuring these options directly in Studio.

## Contributing

Contributions are welcome. Please open issues or pull requests on GitHub. I want to make Azul the best it can be for myself and anybody who wants to use it.
