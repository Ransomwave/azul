import fs from "node:fs";
import path from "node:path";
import { promises as fsp } from "node:fs";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import { SnapshotBuilder } from "./snapshot.js";
import { RojoSnapshotBuilder } from "./snapshot/rojo.js";
import { generateGUID } from "./util/id.js";
import type {
  InstanceData,
  PushConfig,
  PushConfigMessage,
  PushSnapshotMapping,
  RequestPushConfigMessage,
  StudioMessage,
} from "./ipc/messages.js";

interface PushOptions {
  source?: string;
  destination?: string;
  destructive?: boolean;
  usePlaceConfig?: boolean;
  rojoMode?: boolean;
  rojoProjectFile?: string;
}

export class PushCommand {
  private ipc: IPCServer;
  private options: PushOptions;

  constructor(options: PushOptions = {}) {
    this.options = options;
    this.ipc = new IPCServer(config.port, undefined, {
      requestSnapshotOnConnect: false,
    });
  }

  public async run(): Promise<void> {
    if (this.options.rojoMode) {
      log.info(
        "Rojo compatibility mode: ignoring place config; destination becomes a prefix."
      );
      const destSegments = this.options.destination
        ? this.parseDestination(this.options.destination)
        : [];
      const instances = await this.buildRojoInstances(
        destSegments,
        this.options.source
      );
      if (!instances) return;

      const snapshotMappings: PushSnapshotMapping[] = [
        {
          destination: destSegments,
          destructive: Boolean(this.options.destructive),
          instances,
        },
      ];

      await new Promise<void>((resolve) => {
        const sendSnapshot = () => {
          log.info("Studio connected. Sending Rojo compatibility push...");
          this.ipc.send({ type: "pushSnapshot", mappings: snapshotMappings });
          setTimeout(() => {
            this.ipc.close();
            resolve();
          }, 200);
        };

        if (this.ipc.isConnected()) {
          sendSnapshot();
        } else {
          this.ipc.onConnection(sendSnapshot);
        }
      });
      return;
    }

    const mappings = await this.collectMappings();
    if (!mappings || mappings.length === 0) {
      log.error("No push mappings available. Provide -s/-d or place config.");
      return;
    }

    log.info(`Building ${mappings.length} mapping(s) for push...`);

    const snapshotMappings: PushSnapshotMapping[] = [];

    for (const mapping of mappings) {
      const destSegments = mapping.destination;

      if (mapping.rojoMode) {
        log.info(
          `Mapping source ${mapping.source} in Rojo compatibility mode.`
        );
        const instances = await this.buildRojoInstances(
          destSegments,
          mapping.source
        );
        if (!instances) continue;

        snapshotMappings.push({
          destination: destSegments,
          destructive: Boolean(mapping.destructive),
          instances,
        });
        continue;
      }

      const sourceCandidates = this.expandSourceCandidates(mapping.source);
      const sourceDir = sourceCandidates.find((candidate) =>
        fs.existsSync(candidate)
      );

      if (!sourceDir) {
        log.error(
          `Source path not found for push mapping. Tried: ${sourceCandidates.join(
            ", "
          )}`
        );
        continue;
      }

      const builder = new SnapshotBuilder({
        sourceDir,
        destPrefix: destSegments,
        skipSymlinks: true,
      });

      const instances = await builder.build();
      log.success(
        `Prepared ${
          instances.length
        } instances from ${sourceDir} -> ${destSegments.join("/")}`
      );

      snapshotMappings.push({
        destination: destSegments,
        destructive: Boolean(mapping.destructive),
        instances,
      });
    }

    if (snapshotMappings.length === 0) {
      log.error("No push mappings could be prepared (missing source paths).");
      return;
    }

    await new Promise<void>((resolve) => {
      const sendSnapshot = () => {
        log.info("Studio connected. Sending push snapshot...");
        this.ipc.send({ type: "pushSnapshot", mappings: snapshotMappings });
        setTimeout(() => {
          this.ipc.close();
          resolve();
        }, 200);
      };

      if (this.ipc.isConnected()) {
        sendSnapshot();
      } else {
        this.ipc.onConnection(sendSnapshot);
      }
    });
  }

  private async buildRojoInstances(
    destSegments: string[],
    sourceOverride?: string
  ): Promise<InstanceData[] | null> {
    const sourceRootOpt = sourceOverride ?? this.options.source;

    const projectFiles = await this.resolveRojoProjectFiles(sourceRootOpt);
    if (projectFiles.length === 0) {
      log.error(
        "Rojo compatibility mode could not find default.project.json. Provide --rojo-project or point --source to a folder that contains one."
      );
      return null;
    }

    const allInstances: InstanceData[] = [];
    const projectDirs = new Set<string>();

    for (const projectFile of projectFiles) {
      // If a source root was provided, include the relative path from that root to the project file's folder
      let relativeSegments: string[] = [];
      if (sourceRootOpt) {
        const sourceRoot = path.resolve(process.cwd(), sourceRootOpt);
        const projectDir = path.dirname(projectFile);
        projectDirs.add(projectDir);
        const rel = path.relative(sourceRoot, projectDir).replace(/\\/g, "/");
        if (rel && !rel.startsWith("..")) {
          relativeSegments = rel.split("/").filter(Boolean);
        }
      }

      const effectivePrefix = [...destSegments, ...relativeSegments];

      const builder = new RojoSnapshotBuilder({
        projectFile,
        cwd: process.cwd(),
        destPrefix: effectivePrefix,
      });

      log.info(`Preparing Rojo compatibility push from ${projectFile}`);

      try {
        const built = await builder.build();
        allInstances.push(...built);
      } catch (error) {
        log.error(`${error}`);
        return null;
      }
    }

    // Emit loose scripts not covered by a Rojo project (e.g., cmdr.lua, janitor.lua, Promise.lua)
    if (sourceRootOpt) {
      const sourceRoot = path.resolve(process.cwd(), sourceRootOpt);
      const existingFolders = new Set(
        allInstances
          .filter((i) => i.className === "Folder")
          .map((i) => i.path.join("/"))
      );
      const existingPaths = new Set(allInstances.map((i) => i.path.join("/")));

      const loose = await this.collectLooseScripts(
        sourceRoot,
        destSegments,
        projectDirs,
        existingFolders,
        existingPaths
      );
      allInstances.push(...loose);
    }

    if (allInstances.length === 0) {
      log.warn(
        "Rojo compatibility build produced 0 instances. Check project paths and ignores."
      );
    }

    return allInstances;
  }

  private async collectMappings(): Promise<PushConfig["mappings"] | null> {
    // CLI-provided mapping takes priority
    if (this.options.source && this.options.destination) {
      const destSegments = this.parseDestination(this.options.destination);
      if (destSegments.length === 0) {
        log.error(
          "Destination must be a dot-separated path (e.g., ReplicatedStorage.Packages)"
        );
        return null;
      }
      return [
        {
          source: this.options.source,
          destination: destSegments,
          destructive: Boolean(this.options.destructive),
        },
      ];
    }

    if (this.options.usePlaceConfig === false) {
      return null;
    }

    log.info(
      "Waiting for push config from Studio (ServerStorage.Azul.Config)..."
    );
    const config = await this.waitForPushConfig();
    if (!config) {
      return null;
    }

    log.debug("Received push config from Studio.", config);

    const sanitized = config.mappings?.filter((m) =>
      Boolean(m && m.source && m.destination && m.destination.length > 0)
    );

    if (!sanitized || sanitized.length === 0) {
      log.error("Received push config, but no valid mappings were found.");
      return null;
    }

    return sanitized.map((m) => ({
      source: m.source,
      destination: m.destination,
      destructive: Boolean(m.destructive),
      rojoMode: Boolean(m.rojoMode),
    }));
  }

  private parseDestination(input: string): string[] {
    return input
      .split(/[./\\]+/)
      .map((segment) => segment.trim())
      .filter(Boolean);
  }

  private async resolveRojoProjectFiles(
    sourceOverride?: string
  ): Promise<string[]> {
    const cwd = process.cwd();
    const results = new Set<string>();

    const add = (p: string) => {
      const abs = path.resolve(cwd, p);
      if (fs.existsSync(abs)) {
        results.add(abs);
      }
    };

    if (this.options.rojoProjectFile) {
      add(this.options.rojoProjectFile);
      return [...results];
    }

    const sourceRootOpt = sourceOverride ?? this.options.source;

    // Prefer searching under the provided source folder, if any.
    if (sourceRootOpt) {
      const srcRoot = path.resolve(cwd, sourceRootOpt);
      if (!fs.existsSync(srcRoot)) {
        log.warn(`--source path does not exist: ${srcRoot}`);
      } else {
        const direct = path.join(srcRoot, "default.project.json");
        if (fs.existsSync(direct)) {
          results.add(direct);
        }

        const foundInSource = await this.findProjectJsons(srcRoot, 6);
        for (const f of foundInSource) {
          results.add(f);
        }
      }
    }

    // Fallback: project root
    const rootDirect = path.join(cwd, "default.project.json");
    if (fs.existsSync(rootDirect)) {
      results.add(rootDirect);
    }

    const found = await this.findProjectJsons(cwd, 3);
    for (const f of found) {
      results.add(f);
    }

    return [...results];
  }

  /**
   * Breadth-first search for all default.project.json under a root.
   * Skips common vendor/ignored folders.
   */
  private async findProjectJsons(
    root: string,
    maxDepth: number
  ): Promise<string[]> {
    const queue: { dir: string; depth: number }[] = [{ dir: root, depth: 0 }];
    const found: string[] = [];
    const skip = new Set(["node_modules", ".git", "dist", "sync"]);

    while (queue.length > 0) {
      const { dir, depth } = queue.shift()!;
      if (depth > maxDepth) continue;

      let entries: fs.Dirent[];
      try {
        entries = await fsp.readdir(dir, { withFileTypes: true });
      } catch {
        continue;
      }

      // Deterministic order
      entries.sort((a, b) => a.name.localeCompare(b.name));

      for (const entry of entries) {
        if (entry.isFile() && entry.name === "default.project.json") {
          found.push(path.join(dir, entry.name));
        }
      }

      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        if (skip.has(entry.name)) continue;
        queue.push({ dir: path.join(dir, entry.name), depth: depth + 1 });
      }
    }

    return found;
  }

  private async collectLooseScripts(
    root: string,
    destSegments: string[],
    projectDirs: Set<string>,
    emittedFolders: Set<string>,
    emittedPaths: Set<string>
  ): Promise<InstanceData[]> {
    const results: InstanceData[] = [];

    const walk = async (dir: string, relSegments: string[]) => {
      // Skip directories already handled by a Rojo project
      for (const proj of projectDirs) {
        if (dir === proj || dir.startsWith(proj + path.sep)) {
          return;
        }
      }

      let entries: fs.Dirent[];
      try {
        entries = await fsp.readdir(dir, { withFileTypes: true });
      } catch {
        return;
      }

      entries.sort((a, b) => a.name.localeCompare(b.name));

      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await walk(full, [...relSegments, entry.name]);
          continue;
        }

        if (!this.isScriptFile(entry.name)) continue;

        const { className, scriptName } = this.classifyScript(entry.name);
        const destPath = [...destSegments, ...relSegments, scriptName];
        const key = destPath.join("/");
        if (emittedPaths.has(key)) continue;

        this.ensureFolder(destPath.slice(0, -1), results, emittedFolders);
        emittedPaths.add(key);
        results.push({
          guid: generateGUID(),
          className,
          name: scriptName,
          path: destPath,
          source: await fsp.readFile(full, "utf-8"),
        });
      }
    };

    await walk(root, []);
    return results;
  }

  private ensureFolder(
    pathSegments: string[],
    results: InstanceData[],
    emittedFolders: Set<string>
  ): void {
    if (pathSegments.length === 0) return;
    const key = pathSegments.join("/");
    if (emittedFolders.has(key)) return;
    this.ensureFolder(pathSegments.slice(0, -1), results, emittedFolders);
    emittedFolders.add(key);
    results.push({
      guid: generateGUID(),
      className: "Folder",
      name: pathSegments[pathSegments.length - 1],
      path: [...pathSegments],
    });
  }

  private isScriptFile(fileName: string): boolean {
    return fileName.endsWith(".lua") || fileName.endsWith(".luau");
  }

  private classifyScript(fileName: string): {
    className: "Script" | "LocalScript" | "ModuleScript";
    scriptName: string;
  } {
    const normalized = fileName.replace(/\.lua$/i, ".luau");
    const base = normalized.replace(/\.luau$/i, "");

    if (base.endsWith(".server")) {
      return { className: "Script", scriptName: base.replace(/\.server$/, "") };
    }
    if (base.endsWith(".client")) {
      return {
        className: "LocalScript",
        scriptName: base.replace(/\.client$/, ""),
      };
    }
    if (base.endsWith(".module")) {
      return {
        className: "ModuleScript",
        scriptName: base.replace(/\.module$/, ""),
      };
    }
    return { className: "ModuleScript", scriptName: base };
  }

  /**
   * Normalize source path strings from config, preferring the raw value but
   * attempting obvious fixes (e.g., accidental leading '.' before a folder).
   */
  private expandSourceCandidates(source: string): string[] {
    const candidates: string[] = [];
    const cwd = process.cwd();

    const add = (p: string) => {
      const abs = path.resolve(cwd, p);
      if (!candidates.includes(abs)) {
        candidates.push(abs);
      }
    };

    add(source);

    // If someone wrote ".Packages" by mistake, try "Packages"
    if (source.startsWith(".")) {
      const trimmedDot = source.replace(/^\.*/, "");
      if (trimmedDot) add(trimmedDot);
    }

    // If someone prefixed with ./ or .\, resolve both forms
    if (source.startsWith("./") || source.startsWith(".\\")) {
      add(source.slice(2));
    }

    return candidates;
  }

  private async waitForPushConfig(): Promise<PushConfig | null> {
    return new Promise<PushConfig | null>((resolve) => {
      let resolved = false;

      const timeout = setTimeout(() => {
        if (!resolved) {
          log.warn("Timed out waiting for push config from Studio.");
          resolved = true;
          resolve(null);
        }
      }, 8000);

      this.ipc.onMessage((message: StudioMessage) => {
        if (message.type === "pushConfig") {
          const pushConfig = (message as PushConfigMessage).config;

          clearTimeout(timeout);
          if (!resolved) {
            resolved = true;
            resolve(pushConfig);
          }
        }
      });

      // Ask the plugin to send config after connection
      this.ipc.onConnection(() => {
        const request: RequestPushConfigMessage = { type: "requestPushConfig" };
        this.ipc.send(request);
      });
    });
  }
}
