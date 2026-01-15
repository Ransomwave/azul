import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { log } from "../util/log.js";
import type { InstanceData } from "../ipc/messages.js";

interface RojoProject {
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
      options.projectFile ?? "default.project.json"
    );
    this.destPrefix = options.destPrefix ?? [];
  }

  public async build(): Promise<InstanceData[]> {
    const project = await this.loadProjectFrom(this.projectFile);
    this.prepareIgnoreMatchers(project);

    const results: InstanceData[] = [];
    const projectDir = path.dirname(this.projectFile);

    const tree = project.tree ?? {};
    const hasChildren = Object.keys(tree).some((k) => !k.startsWith("$"));
    const rootPath = typeof tree.$path === "string" ? tree.$path : null;

    if (!hasChildren && rootPath) {
      const absRoot = path.resolve(projectDir, rootPath);
      this.ensureFolder([...this.destPrefix], results);
      await this.walkDirectory(
        absRoot,
        [...this.destPrefix],
        results,
        new Set()
      );
    } else {
      await this.walkTree(tree, [], projectDir, results);
    }

    // Stable ordering: shallow-first, then lexical for determinism
    results.sort((a, b) => {
      if (a.path.length !== b.path.length) {
        return a.path.length - b.path.length;
      }
      return a.path.join("/").localeCompare(b.path.join("/"));
    });

    log.success(
      `Rojo compatibility build produced ${results.length} instances`
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
    results: InstanceData[]
  ): Promise<void> {
    for (const [name, value] of Object.entries(node)) {
      if (name.startsWith("$")) continue;
      if (typeof value !== "object" || value === null) continue;

      const pathSegments = [...this.destPrefix, ...parentPath, name];
      await this.emitNode(name, value, pathSegments, projectDir, results);
    }
  }

  private async emitNode(
    name: string,
    node: Record<string, any>,
    pathSegments: string[],
    projectDir: string,
    results: InstanceData[]
  ): Promise<void> {
    const className = this.resolveClassName(node, pathSegments);
    const pathHint = typeof node.$path === "string" ? node.$path : undefined;
    const absPath = pathHint ? path.resolve(projectDir, pathHint) : null;
    const definedChildren = new Set(
      Object.keys(node).filter((key) => !key.startsWith("$"))
    );

    const initScript = absPath ? await this.findInit(absPath) : null;

    // If there's an init script, the folder becomes a ModuleScript at the same path.
    if (initScript) {
      this.ensureFolder(pathSegments.slice(0, -1), results);
      this.moduleContainers.add(pathSegments.join("/"));
      const scriptClass = this.classifyScript(initScript.fileName).className;
      results.push({
        guid: this.makeGuid(),
        className: scriptClass,
        name: pathSegments[pathSegments.length - 1],
        path: [...pathSegments],
        source: initScript.source,
      });
    } else {
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
        results
      );
    }

    // Walk filesystem for $path mappings
    if (absPath && (await this.exists(absPath))) {
      await this.walkDirectory(absPath, pathSegments, results, definedChildren);
    }
  }

  private resolveClassName(
    node: Record<string, any>,
    pathSegments: string[]
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
    definedChildren: Set<string>
  ): Promise<void> {
    if (this.isIgnored(dirPath)) return;

    // If this directory has an init, treat it as a ModuleScript container
    const initScript = await this.findInit(dirPath);
    if (initScript) {
      const key = destPath.join("/");
      // Avoid duplicating ModuleScripts when already emitted from tree walk
      if (!this.moduleContainers.has(key)) {
        this.moduleContainers.add(key);
        this.ensureFolder(destPath.slice(0, -1), results);
        const scriptClass = this.classifyScript(initScript.fileName).className;
        results.push({
          guid: this.makeGuid(),
          className: scriptClass,
          name: destPath[destPath.length - 1] ?? path.basename(dirPath),
          path: [...destPath],
          source: initScript.source,
        });
      }
    } else {
      this.ensureFolder(destPath, results);
    }

    // Sub-project override
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

    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    const initCandidates = this.initCandidatesFor();

    for (const entry of entries) {
      const fullPath = path.join(dirPath, entry.name);
      if (this.isIgnored(fullPath)) continue;

      // Skip entries explicitly defined in the project tree
      if (definedChildren.has(entry.name)) {
        continue;
      }

      if (entry.isDirectory()) {
        this.ensureFolder([...destPath, entry.name], results);
        await this.walkDirectory(
          fullPath,
          [...destPath, entry.name],
          results,
          new Set()
        );
        continue;
      }

      // Skip init files here (handled earlier)
      if (initCandidates.includes(entry.name)) {
        continue;
      }

      if (this.isScriptFile(entry.name)) {
        const baseName = path.parse(entry.name).name;
        if (definedChildren.has(baseName)) {
          continue;
        }
        const { className, scriptName } = this.classifyScript(entry.name);
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
    // ensure parents first
    this.ensureFolder(pathSegments.slice(0, -1), results);
    this.emittedFolders.add(key);
    results.push({
      guid: this.makeGuid(),
      className: "Folder",
      name: pathSegments[pathSegments.length - 1],
      path: [...pathSegments],
    });
  }

  private async findInit(
    dirPath: string
  ): Promise<{ fileName: string; source: string } | null> {
    const candidates = this.initCandidatesFor();

    for (const candidate of candidates) {
      const full = path.join(dirPath, candidate);
      if (await this.exists(full)) {
        const source = await fs.readFile(full, "utf-8");
        return { fileName: candidate, source };
      }
    }

    return null;
  }

  private initCandidatesFor(): string[] {
    const bases = ["init", "init.server", "init.client", "init.module"];

    const variants: string[] = [];
    for (const base of bases) {
      variants.push(`${base}.lua`, `${base}.luau`);
    }

    return [...new Set(variants)];
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

  private async exists(target: string): Promise<boolean> {
    try {
      await fs.access(target);
      return true;
    } catch {
      return false;
    }
  }

  private makeGuid(): string {
    return randomUUID().replace(/-/g, "");
  }
}
