# Super Studio Sync

A two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support via sourcemap generation.

## Philosophy

**Studio is the source of truth.** The local filesystem mirrors what's in Studio, not the other way around.

## Features

- 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- 🗺️ **Automatic sourcemap generation**: Rojo-compatible sourcemap.json for luau-lsp
- 🌳 **DataModel mirroring**: Instance hierarchy mapped to folder structure
- 🔌 **Real-time WebSocket communication**: Instant synchronization
- 🎯 **No manual configuration**: No Rojo project files, no .meta.json needed

## Quick Start

### 1. Install dependencies

```bash
npm install
```

### 2. Start the sync daemon

```bash
npm run dev
```

### 3. Install the Studio plugin

Copy the `plugin/` folder contents to your Roblox Studio plugins directory.

### 4. Connect from Studio

The plugin will automatically connect to `ws://localhost:8080` when Studio starts.

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

```
ReplicatedStorage/
  Modules/
    Foo/
      init.lua        ← ModuleScript "Foo"
      Bar.lua         ← ModuleScript "Bar"
    Enemies/
      Slime/
        AI.lua        ← Script "AI"
```

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
- File extensions (.lua vs .luau)
- Excluded services

## License

MIT
