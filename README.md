# <span><img src="./docs/assets/logo.png" alt="Azul Logo" height="30"></span> Azul

Azul is a two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support, which allows code completion & type checking.

Azul allows you to use professional-grade tools like Visual Studio Code in Roblox development.

_Yes, the name is a pun on Rojo (Spanish for "red"). Azul means "blue"!_

<a href="#quick-start"><b>Quick Start</b></a> — <a href="#why-azul"><b>Why Azul</b></a> — <a href="https://azul-docs.vercel.app"><b>Documentation</b></a>

## Philosophy

Azul treats **Studio as the source of truth**. The local filesystem mirrors what's in Studio, not the other way around.

It avoids the complexity and ambiguity that can come with tools like Rojo: for example, deciding a new Script's parent class, properties, or attributes. Rather than trying to encode Studio state in extra files (i.e. `model.json`, `meta.json`...), Azul lets Studio determine state. This leads to a much simpler and more intuitive workflow.

While Azul mainly follows this philosophy, it doesn't cut you off from the filesystem. Build from local files using the `azul build` command, or selectively push files using `azul push`.

## Features

- - [x] 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- - [x] 🌳 **DataModel mirroring**: Instance hierarchy 1:1 mapped to folder structure
- - [x] 🎯 **No manual config / required structure**: Works out of the box with new and existing Roblox Studio projects, regardless of structure
- - [x] 🏗️ **[Build command](https://azul-docs.vercel.app/getting-started/projects/#build-from-an-existing-local-project)**: Sync your local files into Studio with `azul build`.
- - [x] 📦 **[Push command](https://azul-docs.vercel.app/commands/#azul-push)**: Selectively push local files into Studio using `azul push`. Useful when importing external libraries or using package managers (i.e Wally)
- - [x] 🏛️ **[Fully hermetic builds](https://azul-docs.vercel.app/commands/#azul-pack)**: Fully serialize Instance properties using `azul pack`, allowing for clean, reproductible builds when `build`ing or `push`ing.
- - [x] 🔴 **Rojo compatibility mode**: Supports importing from Rojo projects with the `--rojo` flag.
- - [x] 🗺️ **Automatic sourcemap generation**: Generates a Rojo-compatible `sourcemap.json` so tools like Luau-lsp work out of the box.

## Why Azul?

Because Azul is as simple as it gets: Run the `azul` command in your project folder, connect the companion plugin in Studio & start coding.

Compatible with projects both old and new, no more extra worrying about how to “Rojo-ify” your project. Your code is literally 1:1 mapped to what’s in Studio.

### Why not use Rojo?

Rojo is the industry standard for a reason, but it's built on a specific premise: the filesystem must be the source of truth. While this works for traditional software, it creates a massive "philosophy gap" when applied to a visual, instance-based engine like Roblox.

Whether you use Rojo fully or partially, you run into the same fundamental problems:

- **Fully Managed**: To keep everything on the filesystem, you have to define your entire game hierarchy in JSON or manage opaque `.rbxm` files. This turns a visual engine into a text-config chore.
- **Partially Managed**: Most settle for a hybrid approach to avoid the pitfalls of fully managed, but this also introduces new problems. Your local files are no longer a true reflection of your Studio project, since they are missing literal chunks of your project. This leads to confusion & a fractured workflow where you constantly switch contexts between Studio and your IDE.

Instead of fighting Studio, Azul embraces it as the source of truth and mirrors it to your filesystem in real-time. You get the best of both worlds: the power of external tooling & the seamless, visual workflow of Studio.

### Why not use Roblox Script Sync?

Azul offers several advantages over the upcoming Script Sync feature:

- **Azul mirrors everything**: Script Sync can only sync specified folders and scripts, not entire projects. Azul directly mirrors the entire DataModel, meaning you don't have to worry about manually syncing specific parts of your project.

- **Building from filesystem**: Script Sync is a "live-only" link with no manual override. Azul gives you the `azul build` command, allowing you to forcefully push your local state into Studio. This is essential for maintaining a clean state or recovering from accidental Studio changes.

- **First-class Package Support**: Syncing external libraries or using package managers (Wally, pesde) is seamless with `azul push`. You don't have to manually set up sync roots for every new package you install; Azul just handles it.

- **Rojo compatibility**: Azul can import existing Rojo projects using the `--rojo` & `--rojo-project <file>` flags, making Azul compatible with many existing open source projects.
  - **Generates a Rojo-compatible `sourcemap.json`**: This allows any tooling that require Rojo-style sourcemaps _(like luau-lsp, the language server)_ to work seamlessly.

- **Zero commitment**: Azul requires no commitment to a specific project structure. If you want to try out Script Sync (or any other tool) in the future, Azul won't get in your way.

---

## Quick Start

### Auto-Install (Recommended)

1. Install Node.js from [nodejs.org](https://nodejs.org/).
2. Run the following command in your terminal:
   ```ps1
   npm install azul-sync -g
   ```
3. Install the Azul Companion Plugin to Roblox Studio.
   - **Guide: [Azul Plugin: Install Instructions](/plugin/README.md)**
4. Create a new Folder to house your Azul project and open it in your IDE.
5. With the terminal in your project folder, run:
   ```
   azul
   ```
6. In Roblox Studio, click on the "Connect" button in the Azul plugin.
7. Start coding!
8. _(Optional)_ For the best experience, check out the [Recommended Tools & Extensions](#recommended-tools--extensions).

### Manual Install

1. Clone this repository using Git:
   ```ps1
   git clone https://github.com/Ransomwave/azul.git
   ```
2. Install Node.js from [nodejs.org](https://nodejs.org/) or by using your system's package manager:
   ```ps1
   # Windows (using winget)
   winget install OpenJS.NodeJS.LTS
   # macOS (using Homebrew)
   brew install node
   # Linux (using apt)
   sudo apt install nodejs npm
   ```
3. Install dependencies by running
   ```ps1
   npm install
   ```
4. Build the project
   ```ps1
   npm run build
   ```
5. Install the project globally
   ```ps1
   npm install -g .
   ```
6. Install the Azul Companion Plugin to Roblox Studio.
   - **Guide: [Azul Plugin: Install Instructions](/plugin/README.md)**
7. Create a new Folder to house your Azul project and open it in your IDE.
8. With the terminal in your project folder, run:
   ```ps1
   azul
   ```
9. In Roblox Studio, click on the "Connect" button in the Azul plugin.

## Recommended Tools & Extensions

### VSCode with Luau-LSP

To get the best experience, use [Visual Studio Code](https://code.visualstudio.com/) with the [Luau Language Server extension](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp).

To get IntelliSense working, open your `User Settings (JSON)` from the command palette (`Ctrl+Shift+P` or `Cmd+Shift+P`) and make sure to set up luau-lsp like this:

```json
  "luau-lsp.plugin.enabled": true,
  "luau-lsp.sourcemap.enabled": true,
  "luau-lsp.sourcemap.autogenerate": false,
  "luau-lsp.sourcemap.sourcemapFile": "sourcemap.json",
  "luau-lsp.sourcemap.includeNonScripts": true,
```

This is my recommended setup for Azul projects. That said, Azul is compatible with any IDE or text editor that can edit `.luau` files. Luau-LSP is also available for other editors like [Neovim](https://github.com/lopi-py/luau-lsp.nvim).

### VSCode with Verde

[Verde](https://marketplace.visualstudio.com/items?itemName=Dvitash.verde) is a VSCode extension that mimics the Roblox Studio Explorer and Properties windows. It works great alongside Azul to provide a seamless development experience.

## Contributing

Contributions are welcome! Please open issues or pull requests on GitHub. I want to make Azul the best it can be for myself and anybody who wants to use it.
