import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { log } from "../../util/log.js";
import {
  classifyScriptFileName,
  isInstanceJsonName,
  isScriptFileName,
  ScriptClassName,
} from "../../util/scriptFile.js";
import type { InstanceData } from "../../ipc/messages.js";
import { convertImplicitRojoProperty } from "./convert.js";

interface RojoProject {
  name: string;
  tree: Record<string, any>;
  globIgnorePaths?: string | string[];
}

export interface RojoSnapshotOptions {
  projectFile?: string;
  cwd?: string;
  destPrefix?: string[];
}

/**
 * Builds InstanceData[] from a Rojo-style default.project.json (compat layer).
 */
export class RojoSnapshotBuilder {
  private projectFile: string;
  private cwd: string;
  private emittedFolders: Set<string> = new Set();
  private moduleContainers: Set<string> = new Set();
  private destPrefix: string[];
  private ignoreMatchers: RegExp[] = [];

  constructor(options: RojoSnapshotOptions = {}) {
    this.cwd = path.resolve(options.cwd ?? process.cwd());
    this.projectFile = path.resolve(
      this.cwd,
      options.projectFile ?? "default.project.json",
    );
    this.destPrefix = options.destPrefix ?? [];
  }

  public async build(): Promise<InstanceData[]> {
    const project = await this.loadProjectFrom(this.projectFile);
    this.prepareIgnoreMatchers(project);

    const results: InstanceData[] = [];
    const projectDir = path.dirname(this.projectFile);

    const tree = project.tree ?? {};
    const rootChildren = Object.keys(tree).filter((k) => !k.startsWith("$"));
    const hasChildren = rootChildren.length > 0;
    const rootPath = typeof tree.$path === "string" ? tree.$path : null;

    log.debug(`destPrefix: ${this.destPrefix.join("/")}`);

    // If the root of the project tree doesn't have a $className of "DataModel", the Rojo project is not a Place and
    // we cannot guess the root of the emitted tree.
    if (
      (!tree.$className || tree.$className !== "DataModel") &&
      (!this.destPrefix || this.destPrefix.length === 0)
    ) {
      /**
       * Rojo error:
       * Cannot sync a model as a place. Ensure Rojo is serving a project file that has a DataModel at the root of its tree and try again.
       */
      log.error(
        `Cannot build Rojo compatibility snapshot: project file does not have a DataModel root.`,
      );
      log.error(`To fix this, either:`);
      log.error(
        `- Run "azul push" to specify a destination path that is not the root (e.g. "azul push -s . -d Workspace.${project.name || "RojoProject"} --rojo")`,
      );
      log.error(
        `- Make sure the project file has a DataModel root (e.g. "tree": { "$className": "DataModel", ... })`,
      );
      throw new Error(`Cannot build from Rojo project.`);
    }

    if (rootPath) {
      const absRoot = path.resolve(projectDir, rootPath);
      const rootKind = await this.pathKind(absRoot);

      if (!rootKind) {
        throw new Error(`$path target ${absRoot} does not exist.`);
      }

      if (rootKind === "file") {
        if (hasChildren) {
          throw new Error(
            `Root $path target ${absRoot} is a file and cannot define child nodes.`,
          );
        }

        if (!isScriptFileName(path.basename(absRoot))) {
          throw new Error(
            `$path target ${absRoot} must be a .lua or .luau script file.`,
          );
        }

        const { className, scriptName } = classifyScriptFileName(
          path.basename(absRoot),
        );
        const source = await fs.readFile(absRoot, "utf-8");

        // If the root is a file, it becomes the single instance emitted at the destPrefix (or root if no prefix).
        const destPath =
          this.destPrefix.length === 0
            ? [scriptName]
            : this.destPrefix[this.destPrefix.length - 1] === scriptName
              ? [...this.destPrefix]
              : [...this.destPrefix, scriptName];

        this.ensureFolder(destPath.slice(0, -1), results);
        this.moduleContainers.add(destPath.join("/"));
        results.push({
          guid: this.makeGuid(),
          className,
          name: destPath[destPath.length - 1],
          path: destPath,
          source,
        });
      } else {
        await this.walkDirectory(
          absRoot,
          [...this.destPrefix],
          results,
          new Set(rootChildren),
        );
      }
    }

    // Walk any children defined in the root of the project tree (if $path is not a file)
    if (hasChildren) {
      await this.walkTree(tree, [], projectDir, results);
    }

    // Stable ordering: shallow-first, then lexical for determinism
    results.sort((a, b) => {
      if (a.path.length !== b.path.length) {
        return a.path.length - b.path.length;
      }
      return a.path.join("/").localeCompare(b.path.join("/"));
    });

    log.debug(`Instances emitted in Rojo compatibility build:`);
    for (const instance of results) {
      log.debug(`- ${instance.path.join("/")} (${instance.className})`);
    }

    log.success(
      `Rojo compatibility build produced ${results.length} instances`,
    );
    return results;
  }

  private async loadProjectFrom(file: string): Promise<RojoProject> {
    let raw: string;
    try {
      raw = await fs.readFile(file, "utf-8");
    } catch (error) {
      throw new Error(`Rojo compatibility mode requires ${file} (not found).`);
    }

    try {
      const parsed = JSON.parse(raw) as RojoProject;
      if (!parsed || typeof parsed !== "object" || !parsed.tree) {
        throw new Error("Missing tree key");
      }
      return parsed;
    } catch (error) {
      throw new Error(`Failed to parse Rojo project file at ${file}: ${error}`);
    }
  }

  private prepareIgnoreMatchers(project: RojoProject): void {
    const defaults = [
      "**/.git/**",
      "**/.git",
      "**/.github/**",
      "**/sourcemap.json",
      "**/*.lock",
      "**/~$*",
    ];

    const user = Array.isArray(project.globIgnorePaths)
      ? project.globIgnorePaths
      : project.globIgnorePaths
        ? [project.globIgnorePaths]
        : [];

    const patterns = [...defaults, ...user];
    this.ignoreMatchers = patterns.map((p) => this.globToRegex(p));
  }

  private globToRegex(glob: string): RegExp {
    const escaped = glob.replace(/([|\\{}()\[\]^$+*?.])/g, "\\$1");

    const regex = escaped
      .replace(/\*\*/g, ".*")
      .replace(/\*/g, "[^/]*")
      .replace(/\?/g, "[^/]");

    return new RegExp(`^${regex}$`);
  }

  private isIgnored(absPath: string): boolean {
    const rel = path.relative(this.cwd, absPath).replace(/\\/g, "/");
    for (const matcher of this.ignoreMatchers) {
      if (matcher.test(rel)) {
        return true;
      }
    }
    return false;
  }

  private async walkTree(
    node: Record<string, any>,
    parentPath: string[],
    projectDir: string,
    results: InstanceData[],
  ): Promise<void> {
    for (const [name, value] of Object.entries(node)) {
      if (name.startsWith("$")) continue;
      if (typeof value !== "object" || value === null) continue;

      const pathSegments = [...this.destPrefix, ...parentPath, name];
      await this.emitNode(name, value, pathSegments, projectDir, results);
    }
  }

  public async parseModelFile(
    filePath: string,
    destPath: string[],
  ): Promise<InstanceData[]> {
    let raw: string;
    try {
      raw = await fs.readFile(filePath, "utf-8");
    } catch (error) {
      throw new Error(`Failed to read .model.json at ${filePath}: ${error}`);
    }

    let parsed: any;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      throw new Error(`Failed to parse .model.json at ${filePath}: ${error}`);
    }

    const results: InstanceData[] = [];
    const name = destPath[destPath.length - 1] || "Model";
    await this.parseModelNode(
      parsed,
      name,
      destPath,
      path.dirname(filePath),
      results,
    );
    return results;
  }

  private async parseModelNode(
    node: any,
    name: string,
    currentPath: string[],
    baseDir: string,
    results: InstanceData[],
  ): Promise<void> {
    if (typeof node !== "object" || node === null) return;

    const pathHint = node.$path || node.path;
    if (typeof pathHint === "string") {
      const absPath = path.resolve(baseDir, pathHint);
      const exists = await this.exists(absPath);
      if (!exists) {
        throw new Error(`$path target ${absPath} does not exist.`);
      }

      const kind = await this.pathKind(absPath);
      if (kind === "file") {
        const fileName = path.basename(absPath);
        if (isInstanceJsonName(fileName)) {
          const modelInstances = await this.parseModelFile(
            absPath,
            currentPath,
          );
          results.push(...modelInstances);
          return;
        } else if (this.isJsonModuleFile(fileName)) {
          const source = await this.readJsonModuleSource(absPath);
          this.moduleContainers.add(currentPath.join("/"));
          results.push({
            guid: this.makeGuid(),
            className: "ModuleScript",
            name,
            path: [...currentPath],
            source,
          });
          return;
        } else if (isScriptFileName(fileName)) {
          const { className } = classifyScriptFileName(fileName);
          const source = await fs.readFile(absPath, "utf-8");
          this.moduleContainers.add(currentPath.join("/"));
          results.push({
            guid: this.makeGuid(),
            className,
            name,
            path: [...currentPath],
            source,
          });
          return;
        } else {
          throw new Error(`Unsupported $path file type: ${absPath}`);
        }
      } else if (kind === "dir") {
        await this.walkDirectory(absPath, currentPath, results, new Set());
        return;
      }
    }

    const className =
      node.ClassName || node.className || node.$className || "Folder";

    const rawProperties =
      node.Properties || node.properties || node.$properties;
    const properties: Record<string, any> = {};
    if (rawProperties && typeof rawProperties === "object") {
      for (const [k, v] of Object.entries(rawProperties)) {
        properties[k] = convertImplicitRojoProperty(k, v);
      }
    }

    const rawAttributes =
      node.Attributes || node.attributes || node.$attributes;
    const attributes: Record<string, any> = {};
    if (rawAttributes && typeof rawAttributes === "object") {
      for (const [k, v] of Object.entries(rawAttributes)) {
        attributes[k] = convertImplicitRojoProperty(k, v);
      }
    }

    const rawTags = node.Tags || node.tags || node.$tags;
    let tags: string[] | undefined = undefined;
    if (Array.isArray(rawTags)) {
      tags = rawTags.map((t) => String(t));
    }

    const instance: InstanceData = {
      guid: this.makeGuid(),
      className,
      name,
      path: [...currentPath],
    };

    if (Object.keys(properties).length > 0) {
      instance.properties = properties;
    }
    if (Object.keys(attributes).length > 0) {
      instance.attributes = attributes;
    }
    if (tags && tags.length > 0) {
      instance.tags = tags;
    }

    this.moduleContainers.add(currentPath.join("/"));
    results.push(instance);

    const rawChildren = node.Children || node.children || node.$children;
    if (Array.isArray(rawChildren)) {
      for (let i = 0; i < rawChildren.length; i++) {
        const childNode = rawChildren[i];
        if (typeof childNode === "object" && childNode !== null) {
          const childName =
            childNode.Name ||
            childNode.name ||
            childNode.$name ||
            `Instance${i}`;
          const childPath = [...currentPath, childName];
          await this.parseModelNode(
            childNode,
            childName,
            childPath,
            baseDir,
            results,
          );
        }
      }
    } else if (rawChildren && typeof rawChildren === "object") {
      for (const [childName, childNode] of Object.entries(rawChildren)) {
        if (typeof childNode === "object" && childNode !== null) {
          const childPath = [...currentPath, childName];
          await this.parseModelNode(
            childNode,
            childName,
            childPath,
            baseDir,
            results,
          );
        }
      }
    }
  }

  private async emitNode(
    name: string,
    node: Record<string, any>,
    pathSegments: string[],
    projectDir: string,
    results: InstanceData[],
  ): Promise<void> {
    const className = this.resolveClassName(node, pathSegments);
    const pathHint = typeof node.$path === "string" ? node.$path : undefined;
    const absPath = pathHint ? path.resolve(projectDir, pathHint) : null;
    const definedChildren = new Set(
      Object.keys(node).filter((key) => !key.startsWith("$")),
    );
    const pathKind = absPath ? await this.pathKind(absPath) : null;

    let initScript: {
      fileName: string;
      source: string;
      className?: ScriptClassName;
    } | null = null;
    let initModelFile: string | null = null;

    if (absPath && pathKind === "dir") {
      const modelPath = path.join(absPath, "init.model.json");
      if (await this.exists(modelPath)) {
        initModelFile = modelPath;
      }
      initScript = await this.findInit(absPath);
    } else if (absPath && pathKind === "file") {
      const fileName = path.basename(absPath);
      if (isInstanceJsonName(fileName)) {
        this.ensureFolder(pathSegments.slice(0, -1), results);
        const modelInstances = await this.parseModelFile(absPath, pathSegments);
        if (modelInstances.length > 0) {
          const rootInstance = modelInstances[0];

          if (node.$className) {
            rootInstance.className = node.$className;
          }

          if (node.$properties) {
            const mergedProps = { ...(rootInstance.properties || {}) };
            for (const [k, v] of Object.entries(node.$properties)) {
              mergedProps[k] = convertImplicitRojoProperty(k, v);
            }
            rootInstance.properties = mergedProps;
          }

          if (node.$attributes) {
            const mergedAttrs = { ...(rootInstance.attributes || {}) };
            for (const [k, v] of Object.entries(node.$attributes)) {
              mergedAttrs[k] = v;
            }
            rootInstance.attributes = mergedAttrs;
          }

          if (node.$tags) {
            const existingTags = new Set(rootInstance.tags || []);
            if (Array.isArray(node.$tags)) {
              for (const tag of node.$tags) {
                existingTags.add(String(tag));
              }
            }
            rootInstance.tags = [...existingTags];
          }

          results.push(...modelInstances);
        }

        for (const [childName, childValue] of Object.entries(node)) {
          if (childName.startsWith("$")) continue;
          if (typeof childValue !== "object" || childValue === null) continue;
          await this.emitNode(
            childName,
            childValue,
            [...pathSegments, childName],
            projectDir,
            results,
          );
        }
        return;
      } else if (this.isJsonModuleFile(fileName)) {
        const source = await this.readJsonModuleSource(absPath);
        initScript = { fileName, source, className: "ModuleScript" };
      } else {
        if (!isScriptFileName(fileName)) {
          throw new Error(`$path target ${absPath} is not a .lua/.luau file.`);
        }
        const source = await fs.readFile(absPath, "utf-8");
        initScript = { fileName, source };
      }
    }

    // If there's an init script or an init model file, the folder becomes that instance.
    if (initModelFile) {
      this.ensureFolder(pathSegments.slice(0, -1), results);
      this.moduleContainers.add(pathSegments.join("/"));

      const modelInstances = await this.parseModelFile(
        initModelFile,
        pathSegments,
      );
      if (modelInstances.length > 0) {
        const rootInstance = modelInstances[0];

        if (node.$className) {
          rootInstance.className = node.$className;
        }

        if (node.$properties) {
          const mergedProps = { ...(rootInstance.properties || {}) };
          for (const [k, v] of Object.entries(node.$properties)) {
            mergedProps[k] = convertImplicitRojoProperty(k, v);
          }
          rootInstance.properties = mergedProps;
        }

        if (node.$attributes) {
          const mergedAttrs = { ...(rootInstance.attributes || {}) };
          for (const [k, v] of Object.entries(node.$attributes)) {
            mergedAttrs[k] = v;
          }
          rootInstance.attributes = mergedAttrs;
        }

        if (node.$tags) {
          const existingTags = new Set(rootInstance.tags || []);
          if (Array.isArray(node.$tags)) {
            for (const tag of node.$tags) {
              existingTags.add(String(tag));
            }
          }
          rootInstance.tags = [...existingTags];
        }

        if (initScript) {
          const scriptClass =
            initScript.className ??
            classifyScriptFileName(initScript.fileName).className;
          rootInstance.className = scriptClass;
          rootInstance.source = initScript.source;
        }

        results.push(...modelInstances);
      }
    }

    // If there's an init script, the folder becomes a ModuleScript at the same path.
    else if (initScript) {
      this.ensureFolder(pathSegments.slice(0, -1), results);
      this.moduleContainers.add(pathSegments.join("/"));
      const scriptClass =
        initScript.className ??
        classifyScriptFileName(initScript.fileName).className;
      results.push({
        guid: this.makeGuid(),
        className: scriptClass,
        name: pathSegments[pathSegments.length - 1],
        path: [...pathSegments],
        source: initScript.source,
      });
    }
    // If no special file (model or script) was found, emit a standard instance.
    else {
      this.ensureFolder(pathSegments.slice(0, -1), results);
      results.push({
        guid: this.makeGuid(),
        className,
        name,
        path: [...pathSegments],
      });
    }

    // Recurse into children defined in JSON
    for (const [childName, childValue] of Object.entries(node)) {
      if (childName.startsWith("$")) continue;
      if (typeof childValue !== "object" || childValue === null) continue;
      await this.emitNode(
        childName,
        childValue,
        [...pathSegments, childName],
        projectDir,
        results,
      );
    }

    // Walk filesystem for $path mappings
    if (absPath && pathKind === "dir") {
      await this.walkDirectory(absPath, pathSegments, results, definedChildren);
    }
  }

  private resolveClassName(
    node: Record<string, any>,
    pathSegments: string[],
  ): string {
    if (typeof node.$className === "string") {
      return node.$className;
    }
    if (pathSegments.length === 1) {
      // Service root
      return pathSegments[0];
    }
    return "Folder";
  }

  private async walkDirectory(
    dirPath: string,
    destPath: string[],
    results: InstanceData[],
    definedChildren: Set<string>,
  ): Promise<void> {
    if (this.isIgnored(dirPath)) return;

    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    const initCandidates = this.getInitCandidates();

    // If this directory has an init, the directory becomes that script; children attach under it
    const initEntry = entries.find(
      (e) => e.isFile() && initCandidates.includes(e.name),
    );

    const initModelEntry = entries.find(
      (e) => e.isFile() && e.name === "init.model.json",
    );

    const handledEntries = new Set<string>();
    const key = destPath.join("/");

    if (initModelEntry) {
      handledEntries.add("init.model.json");
      if (!this.moduleContainers.has(key)) {
        this.moduleContainers.add(key);
        this.ensureFolder(destPath.slice(0, -1), results);

        const modelInstances = await this.parseModelFile(
          path.join(dirPath, "init.model.json"),
          destPath,
        );
        if (modelInstances.length > 0) {
          const rootInstance = modelInstances[0];
          if (initEntry) {
            handledEntries.add(initEntry.name);
            const scriptClass = classifyScriptFileName(
              initEntry.name,
            ).className;
            const source = await fs.readFile(
              path.join(dirPath, initEntry.name),
              "utf-8",
            );
            rootInstance.className = scriptClass;
            rootInstance.source = source;
          }
          results.push(...modelInstances);
        }
      }
    } else if (initEntry) {
      handledEntries.add(initEntry.name);
      if (!this.moduleContainers.has(key)) {
        this.moduleContainers.add(key);
        this.ensureFolder(destPath.slice(0, -1), results);
        const scriptClass = classifyScriptFileName(initEntry.name).className;
        const source = await fs.readFile(
          path.join(dirPath, initEntry.name),
          "utf-8",
        );
        results.push({
          guid: this.makeGuid(),
          className: scriptClass,
          name: destPath[destPath.length - 1] ?? path.basename(dirPath),
          path: [...destPath],
          source,
        });
      }
    } else {
      this.ensureFolder(destPath, results);
    }

    // Sub-project overrides
    const subProjectPath = path.join(dirPath, "default.project.json");
    if (await this.exists(subProjectPath)) {
      const previousProjectFile = this.projectFile;
      const previousIgnore = this.ignoreMatchers;
      this.projectFile = subProjectPath;

      const subProject = await this.loadProjectFrom(subProjectPath);
      this.prepareIgnoreMatchers(subProject);
      await this.walkTree(subProject.tree ?? {}, destPath, dirPath, results);

      this.projectFile = previousProjectFile;
      this.ignoreMatchers = previousIgnore;
      return;
    }

    for (const entry of entries) {
      if (handledEntries.has(entry.name)) continue;
      const fullPath = path.join(dirPath, entry.name);
      if (this.isIgnored(fullPath)) continue;

      // Skip entries explicitly defined in the project tree
      if (definedChildren.has(entry.name)) {
        continue;
      }

      if (
        entry.isFile() &&
        entry.name.endsWith(".model.json") &&
        entry.name !== "init.model.json"
      ) {
        handledEntries.add(entry.name);
        const baseName = entry.name.slice(0, -".model.json".length);
        if (definedChildren.has(baseName)) {
          continue;
        }

        this.ensureFolder(destPath, results);
        const modelInstances = await this.parseModelFile(fullPath, [
          ...destPath,
          baseName,
        ]);
        if (modelInstances.length > 0) {
          const rootInstance = modelInstances[0];
          const companionScript = entries.find(
            (e) =>
              e.isFile() &&
              isScriptFileName(e.name) &&
              classifyScriptFileName(e.name).scriptName === baseName,
          );
          if (companionScript) {
            handledEntries.add(companionScript.name);
            const scriptClass = classifyScriptFileName(
              companionScript.name,
            ).className;
            const source = await fs.readFile(
              path.join(dirPath, companionScript.name),
              "utf-8",
            );
            rootInstance.className = scriptClass;
            rootInstance.source = source;
          }
          results.push(...modelInstances);
        }
        continue;
      }

      if (entry.isDirectory()) {
        await this.walkDirectory(
          fullPath,
          [...destPath, entry.name],
          results,
          new Set(),
        );
        continue;
      }

      // Skip init files here (handled earlier)
      if (initCandidates.includes(entry.name)) {
        continue;
      }

      if (this.isJsonModuleFile(entry.name)) {
        const baseName = path.parse(entry.name).name;
        if (definedChildren.has(baseName)) {
          continue;
        }
        const source = await this.readJsonModuleSource(fullPath);
        this.ensureFolder(destPath, results);
        results.push({
          guid: this.makeGuid(),
          className: "ModuleScript",
          name: baseName,
          path: [...destPath, baseName],
          source,
        });
        continue;
      }

      if (isScriptFileName(entry.name)) {
        const baseName = path.parse(entry.name).name;
        if (definedChildren.has(baseName)) {
          continue;
        }
        const { className, scriptName } = classifyScriptFileName(entry.name);
        if (definedChildren.has(scriptName)) {
          continue;
        }
        const source = await fs.readFile(fullPath, "utf-8");
        this.ensureFolder(destPath, results);
        results.push({
          guid: this.makeGuid(),
          className,
          name: scriptName,
          path: [...destPath, scriptName],
          source,
        });
      }
    }
  }

  /**
   * Ensure a Folder chain exists for the given path.
   */
  private ensureFolder(pathSegments: string[], results: InstanceData[]): void {
    if (pathSegments.length === 0) return;
    const key = pathSegments.join("/");
    if (this.moduleContainers.has(key)) return;
    if (this.emittedFolders.has(key)) return;
    this.ensureFolder(pathSegments.slice(0, -1), results);
    this.emittedFolders.add(key);
    results.push({
      guid: this.makeGuid(),
      className: "Folder",
      name: pathSegments[pathSegments.length - 1],
      path: [...pathSegments],
    });
  }

  /**
   * Finds an init script (init.lua, init.server.luau, etc.) in a directory.
   * @param dirPath
   * @returns The file name and source of the init script, or null if not found.
   */
  private async findInit(
    dirPath: string,
  ): Promise<{ fileName: string; source: string } | null> {
    const candidates = this.getInitCandidates();

    for (const candidate of candidates) {
      const full = path.join(dirPath, candidate);
      if (await this.exists(full)) {
        const source = await fs.readFile(full, "utf-8");
        return { fileName: candidate, source };
      }
    }

    return null;
  }

  /**
   * Returns a list of potential init script filenames.
   */
  private getInitCandidates(): string[] {
    const bases = ["init", "init.server", "init.client", "init.module"];

    const variants: string[] = [];
    for (const base of bases) {
      variants.push(`${base}.lua`, `${base}.luau`);
    }

    return [...new Set(variants)];
  }

  private isJsonModuleFile(fileName: string): boolean {
    if (!fileName.endsWith(".json")) return false;
    if (fileName === "default.project.json") return false;
    if (fileName.endsWith(".model.json")) return false;
    return true;
  }

  private async readJsonModuleSource(filePath: string): Promise<string> {
    let parsed: unknown;
    try {
      const raw = await fs.readFile(filePath, "utf-8");
      parsed = JSON.parse(raw) as unknown;
    } catch (error) {
      throw new Error(`Failed to parse JSON module at ${filePath}: ${error}`);
    }

    return `return ${this.jsonToLuau(parsed, 0)}`;
  }

  private jsonToLuau(value: unknown, indent: number): string {
    if (value === null || value === undefined) {
      return "nil";
    }

    switch (typeof value) {
      case "string":
        return JSON.stringify(value);
      case "number":
      case "boolean":
        return String(value);
      case "object":
        break;
      default:
        return "nil";
    }

    if (Array.isArray(value)) {
      if (value.length === 0) {
        return "{}";
      }

      const indentStr = "\t".repeat(indent);
      const childIndent = "\t".repeat(indent + 1);
      const parts = value.map(
        (entry) => `${childIndent}${this.jsonToLuau(entry, indent + 1)},`,
      );
      return `{
${parts.join("\n")}
${indentStr}}`;
    }

    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length === 0) {
      return "{}";
    }

    const indentStr = "\t".repeat(indent);
    const childIndent = "\t".repeat(indent + 1);
    const parts = entries.map(([key, entryValue]) => {
      const formattedKey = this.isLuaIdentifier(key)
        ? key
        : `[${JSON.stringify(key)}]`;
      return `${childIndent}${formattedKey} = ${this.jsonToLuau(
        entryValue,
        indent + 1,
      )},`;
    });

    return `{
${parts.join("\n")}
${indentStr}}`;
  }

  private isLuaIdentifier(value: string): boolean {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) return false;
    const keywords = new Set([
      "and",
      "break",
      "do",
      "else",
      "elseif",
      "end",
      "false",
      "for",
      "function",
      "if",
      "in",
      "local",
      "nil",
      "not",
      "or",
      "repeat",
      "return",
      "then",
      "true",
      "until",
      "while",
      "const",
      "export",
    ]);
    return !keywords.has(value);
  }

  private async exists(target: string): Promise<boolean> {
    try {
      await fs.access(target);
      return true;
    } catch {
      return false;
    }
  }

  private async pathKind(target: string): Promise<"file" | "dir" | null> {
    try {
      const stat = await fs.stat(target);
      if (stat.isDirectory()) return "dir";
      if (stat.isFile()) return "file";
      return null;
    } catch {
      return null;
    }
  }

  private makeGuid(): string {
    return randomUUID().replace(/-/g, "");
  }
}
