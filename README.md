# <span><img src="./docs/assets/logo.png" alt="Azul Logo" height="30"></span> Azul

Azul is a two-way synchronization tool between Roblox Studio and your local filesystem with full Luau-LSP support, which allows code completion & type checking.

Azul allows you to use professional-grade tools like Visual Studio Code in Roblox development.

_Yes, the name is a pun on Rojo (Spanish for "red"). Azul means "blue"!_

<a href="#quick-start"><b>Quick Start</b></a> — <a href="#why-azul"><b>Why Azul</b></a> — <a href="https://github.com/Ransomwave/azul/wiki"><b>Documentation</b></a>

## Philosophy

Azul treats **Studio as the source of truth**. The local filesystem mirrors what's in Studio, not the other way around.

Azul avoids the complexity and ambiguity that can come with tools like Rojo: for example, deciding a new Script's parent class, properties, or attributes. Rather than trying to encode Studio state in extra files (e.g. `*.meta.json`), Azul lets Studio be the source of truth. This, in my opinion, leads to a much simpler and more intuitive workflow.

Azul also allows pushing local files into Studio using the `azul build` command, which creates or overwrites instances in Studio based on your local files.

## Features

- - [x] 🔄 **Bi-directional sync**: Changes in Studio update files, and file edits update Studio
- - [x] 🏗️ **[Build command](https://github.com/Ransomwave/azul/wiki/Getting-started#building-from-an-existing-project)**: `azul build` one-time pushes your local files into Studio (creates or overwrites, never deletes)
- - [x] 📦 **[Push command](https://github.com/Ransomwave/azul/wiki/Commands#azul-push)**: `azul push` selectively pushes local files. Useful when importing external libraries or using package managers (i.e Wally)
- - [x] 🔴 **Rojo compatibility mode**: Supports importing from Rojo projects with the `--rojo` flag.
- - [x] 🌳 **DataModel mirroring**: Instance hierarchy 1:1 mapped to folder structure
- - [x] 🎯 **No manual config / required structure**: Works out of the box with new and existing Roblox Studio projects, regardless of structure.
- - [x] 🗺️ **Automatic sourcemap generation**: Generates a Rojo-compatible `sourcemap.json` so tools like Luau-lsp work out of the box.

## Why Azul?

Because Azul is as simple as it gets: Run the azul command in your project folder, connect the companion plugin in Studio & start coding.

Compatible with projects both old and new, no more extra worrying about how to “Rojo-ify” your project. Your code is literally 1:1 mapped to what’s in Studio.

### Rojo already exists, why make another tool?

While Rojo is a powerful tool, I don't believe it's always the best fit for every developer or project. Otherwise trivial tasks in Studio, like inserting a Script inside Tool or Model, suddenly become non-trivial challenges. Rojo just lacks the flexibility of Studio.

Azul is my approach to solve these issues. I built Azul for workflows similar to mine: Studio-first developers who'd rather manage their projects in the dedicated environment instead of fighting with meta files.

### Why not use the upcoming Script Sync feature?

Azul offers several advantages over the upcoming Script Sync feature:

- **Azul mirrors everything**: Script Sync can only sync specified folders and scripts, not entire projects. Azul directly mirrors the entire DataModel, meaning you don't have to worry about manually syncing specific parts of your project.

- **Building from filesystem**: Script Sync only syncs changes made in Studio to the filesystem. Azul allows you to push changes from your local files into Studio using the `azul build` command.

- **Pushing from filesystem**: Sync any code you have stored locally directly to your desired destination using `azul push`. Useful when importing external libraries (e.g. GitHub) or when using Package Managers (e.g. Wally, pesde)

- **Rojo compatibility**: Azul can import existing Rojo projects using the `--rojo` & `--rojo-project=<ProjectFile>` flags, making Azul compatible with many existing open source projects.

  - **Generates a Rojo-compatible `sourcemap.json`**: This allows any tooling that require Rojo-style sourcemaps _(like luau-lsp, the language server)_ to work seamlessly.

- **You can use it today!**: Azul requires no commitment to a specific project structure. If you want to try out Script Sync (or any other tool) in the future, Azul won't get in your way.

---

## Quick Start

### Auto-Install (Recommended)

1. Clone this repository or [download it as a ZIP](https://github.com/Ransomwave/azul/archive/refs/heads/main.zip) and extract it.
2. Inside the extracted folder, locate the `/scripts` Folder
3. Run the install script for your OS (`install-windows.ps1`, `install-macos-linux.sh`).
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

### Recommended: VSCode with Verde

[Verde](https://marketplace.visualstudio.com/items?itemName=Dvitash.verde) is a VSCode extension that mimics the Roblox Studio Explorer and Properties windows. It works great alongside Azul to provide a seamless development experience.

## Contributing

Contributions are welcome! Please open issues or pull requests on GitHub. I want to make Azul the best it can be for myself and anybody who wants to use it.
