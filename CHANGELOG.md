# Changelog

## [Unreleased]

### Daemon

- Performance: Coalesces sourcemap writes & empty directory cleanups.
  - A burst of changes now results in a single write instead of one per message.
- Performance: Skips writing scripts whose content didn't change.
  - Editors & luau-lsp no longer re-check files that weren't touched.
- Removes the `degit` dependency. The `rbx-dom-lua` vendor script now pulls from GitHub tarballs.

### Plugin

- Excludes descendants of `Players` from being processed.
  - These are runtime `Player` objects that can't be rebuilt, so only the service itself is kept.
- Fix: A single instance failing to apply (i.e. a protected `Name` write) no longer aborts the whole build. It's skipped with a warning instead.
- Improves WebSocket connection handling and cleanup logic
  - Connecting to the Daemon is now blazing fast when auto-connect is enabled.
- Updates `rbx-dom-lua` to latest.

## [2.3.0]

This minor release notably adds Solo playtest output streaming, letting you see your Studio console output directly in the Daemon terminal. It also brings a new notification system to the plugin, reminding you to sync Places you've synced before, and a few QOL improvements.

### Daemon

- Adds playtest output streaming (#72) (resolves #26)
  - Output from Studio is relayed to the Daemon terminal during a Solo playtest.
  - Warnings & errors keep their colors, and recognized stack trace locations are mapped to your synced files so you can `Ctrl+Click` on them.
- Rejects additional Studio connections while a session is already syncing with the Daemon. Previously, a second Studio session would take over and overwrite the first one's files. (fixes #74)
- Performance: File path collision checks now use a O(1) lookup map instead of scanning every tracked file.
- Fix: `build`, `push` & `pack` now wait for the WebSocket server to fully close before exiting.

### Plugin

- New: Notifications (resolves #75)
  - Pop-up notifications for important events: connecting, disconnecting, build/push results, version mismatches, Daemon errors & connection failures.
  - Optionally plays a sound when a notification appears.
- New: Sync Reminders (resolves #70)
  - When opening a Place you've previously synced, a notification reminds you to connect again
- New configs:
  - "Stream Console Output": Streams playtest output to the Daemon terminal. (Disabled by default.)
  - "Notifications" & "Notification Sounds"
  - "Sync Reminders"
- New: Slider UI component for some configurations.
- Shows a notification and stops auto-connecting when the Daemon is busy with another Studio session.
- Push messages now show the destination with `.` separators (e.g. `Workspace.Foo`) instead of `/`.
- Migrates the UI from `dervexhero/fusion-03-dev` to mainline Fusion 0.3 (`elttob/fusion`).
- Adds a `plugin:build` script for building the plugin in this repository.

## [2.2.0]

This release notably migrates the serialization format from Azul's own solution to the community standard `rbx-dom-lua`. While `"packVersion": 1` remains supported, it is heavily encouraged to re-run `azul pack` on your projects to take advantage of the new format.

Migrating to this standard format opens the door for many new exciting features, like generating Rojo Project files (#69), `.rbxm` building (#27) & more!

### Daemon

- Migrates serialization logic to `rbx-dom-lua` (resolves #65)
- Updates `packVersion` to `2`
- Rojo Compatibility:
  - Fixes `ignoreGlobPaths` pattern matching
  - Dedupes Rojo instances by path so class conflicts collapse
  - Adds Rojo `Ref` handling
  - Removes conversion of rbx-dom -> Azul format, as they now speak the same format
- Pack: Includes scripts when running `pack` as opposed to only editing the sourcemap (#73)

### Plugin

- Migrates serialization logic to `rbx-dom-lua`
- Fixes Websocket URL being hardcoded to `ws://localhost:8080` instead of pulling from `Config`
- Removes the need for an explicit `ws://` protocol prefix for the Websocket URL, however, a protocol can still be prepended if needed (i.e. `ws://`, `wss://`..)

## [2.1.0]

This minor release notably unifies the versioning system between the Daemon and Plugin (the plugin no longer tracks the Roblox Marketplace version). It also brings a few improvements to the Daemon interactive CLI and bug fixes.

### Daemon

- Adds version mismatch checks (resolves #63)
- CLI Rework: Remakes the interactive CLI interface to be much nicer & friendlier. (#64)
  - Adds a nice Sourcemap selector if more than one is present when using `build` or `push`
- Unifies the build and push interactive flows.
- Push: Properly handles Azul-style nesting (`Foo.luau` & `Foo/Bar.luau`) when the source is that file or folder.
  - For example, before, running `azul push -s Foo.luau -d Workspace` would only create `Foo`. Now, it properly creates the nested structure `Foo` + `Foo.Bar`.
- Fix: `@self` requires are rewritten according to the final Instance name instead of the raw filename.
- Build: Keeps sourcemap properties when falling back to filesystem.
- When version checking, caches the result for 1 hour instead of requesting NPM every time.

### Plugin

- New config: "Ignored ClassNames". Excludes all instances with that `ClassName` from being processed.
  - Note that this is implemented using `Instance.ClassName`. It doesn't respect inheritance like `:IsA` does. This is intended!
- Adds version mismatch checks.
- Updates links from legacy docs website (https://azul-docs.vercel.app) to new one (https://azul.ransomwave.games).

## [2.0.0]

_Plugin v46_

This major release adds live filesystem syncing _(a.k.a. true two-way sync)_. This feature is designed to solve the long-standing feature request of being able to manage your Studio tree directly from your filesystem. This includes creating, deleting, renaming, moving, changing types & nesting files (Scripts). It also attempts to keep any non-Script descendants during any filesystem action.

While this mechanism has been heavily tested by myself in real, production projects - bugs may still arise under edge-cases! If you find one, please [open an issue](https://github.com/Ransomwave/azul/issues).

If you wish this to be disabled and return to old behavior, you can disable `liveFsSync` through `azul config` (`liveFsSync.enabled`)

### Daemon

- Added true two-way syncing (filesystem changes replicate to Studio) (resolves #34)
- New command: `azul open-studio` (resolves #57)
  - Lets you easily open the Place associated with a sourcemap directly from the CLI.
- Pack command: Refactored to work more reliably, especially with the `-o` flag
- Push command: Automatically replaces `@self` requires with `./filename/` to prevent issues with local tooling (fixes #62)
- Upgrade Chokidar dependency to 5.0.0 (resolves #60)
- Upgrade TypeScript version to 7.0.2

### Plugin

- True two-way sync support
- Auto-open toggle (#58)
- Remove internal "Legacy UI"

### [Docs](https://azul.ransomwave.games/)

- Refactored the "Advanced Usage" section into separate pages.
- Added: [Distributing Code](https://azul.ransomwave.games/advanced/distributing-code/)
  - Good read if you want to distribute your projects effectively with Azul
- Updated: [Package Management](https://azul.ransomwave.games/advanced/package-management/)
  - Updated with recommendations on Package Managers.
- Updated: [Rojo Compatibility](https://azul.ransomwave.games/advanced/rojo-compatibility/)
  - Added a handy list of supported Rojo features

## [1.7.0]

_Plugin v45_

### Daemon

- Remove instances moved to excluded parents (#50)
- Rename GUID-suffixed scripts when name conflicts are resolved (#52)

### Plugin

- Setup per-instance listeners after successful handshake instead of every connection attempt
  - Fixes lag spikes when leaving AutoConnect on.
- Serializer: Serialize script-accessible properties that are still marked as `Serialized = false` (fixes #54)
  - Fixes an edge case where [`SerializationService`](https://create.roblox.com/docs/reference/engine/classes/SerializationService) marks the `Part0` & `Part1` of `WeldConstraint`s as `Serialized = false`, preventing `azul pack` from serializing it properly. This fix takes a preventive approach and opts to serialize every property that is script-accessible.
- `--destructive` builds: Skip `Terrain` instance instead of attempting to `Destroy`. (closes #53)
- Replace all Info-level `print`s with `LogService:Info` (blue output)

## [1.6.0]

_Plugin v44_

### Daemon

- Rojo Compatibility:
  - Add support for `*.model.json` instances (#44)
  - Fix "DataModel" being mistakingly spelled "Datamodel", which caused Azul to refuse to build some Rojo projects
- Add unit tests for the repository

### Plugin

- Add auto-connect option (#42)
  - This option runs in the background & keeps attempting to re-connect to the Daemon. This should help mitigate the manual friction of clicking "Connect" every time you want to perform an action.
- Migrate usage of `script.Source` to the new `ScriptEditorService` API. (#47)
  - This change finally allows Azul to behave nicely with Roblox Drafts, whereas before it was unable to see/edit them.

## [1.5.0]

_Plugin v43_

### Daemon

- Add "Handshake" protocol between Daemon <-> Plugin.
  - Azul is now both more reliable and more explicit when connecting to the Daemon. Previous behavior showed the Plugin as "Connected", but that could be misleading as it only meant a connection to the WebSocket instead of the Daemon. This has been remedied with a formal "handshake" both Daemon and Plugin must do before communicating.

### Plugin

- Add MeshPart support for 1:1 builds.
- Auto exclude non-JSON-encodable instances from outbound sync instead of failing silently (#37)
  - This fixes an edge-case where some users would get an obtuse error when trying to sync because their Workspace contained instances with weird names.
- Rojo Compatibility: Add support for JSON modules
- Redesign UI & UX.
- Miscellaneous small improvements.

## [1.4.0]

_Plugin v42_

### Daemon

- Add ability to push standalone files with `azul push`.
  - Files, like directories, can take properties from the sourcemap by passing `--from-sourcemap`.
- Rojo Compatibility improvements:
  - Fix bug where the Rojo Snapshot Builder would not parse the project JSON correctly, causing parts of the project to be missing. (traverses `$path` even when children are defined)
  - Disallow `build`ing Rojo project JSONs that are set up as Models (projects without a `className: "Datamodel"` under `$tree`). Attempting to build this kind of Rojo project will direct you to use `azul push` instead.
- Add automatic update check; warns if there's a new Daemon version available.
- Add new setting: `checkForUpdates: boolean`, enabled by default.
  - When `true`, it will check if your Daemon version is outdated through https://www.npmjs.com/.
- The `config.json` gets automatically populated with default values if they are not explicitly defined.
- Add prettier formatting for `azul --help`.
- Add color formatting for warn and error logs.

### Plugin

- Add button for opening/creating [per-place Daemon config](https://azul-docs.vercel.app/advanced-usage/#per-place-daemon-configuration).
- UI: Add [builder icons](https://kaan650.github.io/builder-icons/) to a few buttons.
- Multiple codebase improvements & refactorings.

### Documentation Improvements

- Updated the main `README.md` to clarify Azul's philosophy versus Rojo and Script Sync, with improved explanations and a more user-friendly comparison of workflows.
- Enhanced the `plugin/README.md` with clearer build instructions and an important note about current installation requirements.

## [1.3.5]

_Plugin v41_

### Daemon

- Add `--destructive` flag for `azul build`
  - Allows you to get clean builds from filesystem instead of manually clearing your place or using an empty one.
- Implement graceful shutdown when shutting down by CTRL+C
- Remove sourcemap question from interactive `build` menu if place config is used.
- Small fixes & QOL patches

### Plugin

- New field in per-place Daemon configuration: `fromSourcemap`
  ```
  fromSourcemap = "./sourcemap.json"
  ```
- Don't override previous DockWidget enabled state.
  - (the Plugin widget won't ignore if you closed it last session)
- More explicit error in WebSocket message processing.
- Fix: Building to "protected" containers (i.e. `StarterPlayer`).
- Fix: Azul should no longer try to write to non-script instances in certain edge cases.

## [1.3.4]

_Plugin v40_

### Daemon

- Remove legacy HTTP polling support
- Fix disambiguated script handling not appending the script type suffix (e.g. `.client.luau`)
- Disambiguated scripts no longer `push`/`build` with the GUID suffix included

### Plugin

- Fix possible memory leak by wrapping listener setup in pcall (#19)
- Display current version text (can be found at the bottom of settings)

## [1.3.3]

- Implemented source-matching between studio scripts and filesystem scripts for better anti-echo behavior (#23, by @Dvitash)

## [1.3.1]

### Daemon

- **1:1 hermetic builds**: `azul build` & `azul push` now support taking a `sourcemap.json` as input.
- `azul pack`: Fully serializes your Place inside a `sourcemap.json`. You can choose between serializing the entire Place or only Scripts & Descendants.
  - Supports serializing all Roblox data types.
  - Limitations: Terrain, `MeshPart.MeshId`, CSG Parts.
  ```diff
  {
    "name": "AzulSync",
    "className": "Script",
    "guid": "1058073",
    "filePaths": [
      "sync/ReplicatedFirst/AzulCompanionPlugin/Actor/AzulSync.server.luau"
    ],
  +  "properties": {
  +    "RunContext": {
  +      "__type": "EnumItem",
  +      "enumType": "RunContext",
  +      "name": "Plugin"
  +    }
  +  }
  }
  ```
- Add interactive mode to `azul build`, `azul push` & `azul pack` for better UX. Passing in flags (i.e. `--from-sourcemap`) allows to skip interactive steps.
- Published the Daemon as an NPM package. Install & Update in one command.
  ```ps1
  npm i azul-sync -g
  npm update -g azul-sync
  ```
- Remove manual install scripts

### Plugin

- Batch Script updates originating from Studio instead of sending each key individually
- Add configuration for Instance batching and Script batching debounces
- Save selected settings scope instead of always falling back to "Global"
- Add "Reload Sourcemap" button to allow for manually reloading the sourcemap
- Remove old "Clear Legacy GUIDs" button
- Several UI improvements

> Note: Support for `MeshPart.MeshId` is planned in the future.
