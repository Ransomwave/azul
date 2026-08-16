import * as fs from "fs";
import * as path from "path";
import { TreeNode } from "./treeManager.js";
import type { FileEventType } from "./watcher.js";
import { config } from "../config.js";
import { log } from "../util/log.js";

/**
 * Mapping of GUID to file path
 */
export interface FileMapping {
  guid: string;
  filePath: string;
  className: string;
}

/**
 * Handles writing the virtual tree to the filesystem
 */
export class FileWriter {
  private baseDir: string;
  private fileMappings: Map<string, FileMapping> = new Map();
  private pathToGuid: Map<string, string> = new Map(); // Reverse index for O(1) path lookups
  private eventSuppressor:
    | ((filePath: string, event: FileEventType) => void)
    | null = null;

  constructor(baseDir: string = config.syncDir) {
    this.baseDir = path.resolve(baseDir);
    this.ensureDirectory(this.baseDir);
  }

  /**
   * Register a callback used to suppress watcher echo events for filesystem
   * mutations the daemon performs itself (create/delete of files and folders).
   * Without this, a daemon-originated write/delete is re-observed by the watcher
   * and mistaken for a user action.
   */
  public setEventSuppressor(
    fn: (filePath: string, event: FileEventType) => void,
  ): void {
    this.eventSuppressor = fn;
  }

  private suppressEvent(filePath: string, event: FileEventType): void {
    this.eventSuppressor?.(filePath, event);
  }

  /**
   * Write all script nodes to the filesystem
   */
  public writeTree(nodes: Map<string, TreeNode>): void {
    log.info("Writing tree to filesystem...");

    // Clear existing mappings
    this.fileMappings.clear();
    this.pathToGuid.clear();

    // Collect all script nodes for batch writing
    const scriptNodes: TreeNode[] = [];
    for (const node of nodes.values()) {
      if (this.isScriptNode(node)) {
        scriptNodes.push(node);
      }
    }

    this.writeBatch(scriptNodes);

    log.success(`Wrote ${this.fileMappings.size} scripts to filesystem`);
  }

  /**
   * Write multiple scripts in a batch for improved I/O efficiency
   */
  public writeBatch(nodes: TreeNode[]): void {
    // Pre-compute all file paths and collect writes
    const writes: { node: TreeNode; filePath: string; dirPath: string }[] = [];
    const dirsToCreate = new Set<string>();
    const batchPathToGuid = new Map<string, string>();

    for (const node of nodes) {
      if (!this.isScriptNode(node) || node.source === undefined) continue;
      const filePath = this.getFilePathWithCollisionMap(node, batchPathToGuid);
      const dirPath = path.dirname(filePath);
      writes.push({ node, filePath, dirPath });
      dirsToCreate.add(dirPath);
      batchPathToGuid.set(path.resolve(filePath), node.guid);
    }

    // Batch create all directories first (sorted by depth to ensure parents exist)
    const sortedDirs = Array.from(dirsToCreate).sort(
      (a, b) => a.length - b.length,
    );
    for (const dir of sortedDirs) {
      this.ensureDirectory(dir);
    }

    for (const { node, filePath } of writes) {
      try {
        fs.writeFileSync(filePath, node.source!, "utf-8");

        this.fileMappings.set(node.guid, {
          guid: node.guid,
          filePath: filePath,
          className: node.className,
        });
        this.pathToGuid.set(path.resolve(filePath), node.guid);

        log.script(this.getRelativePath(filePath), "updated");
      } catch (error) {
        log.error(`Failed to write script ${filePath}:`, error);
      }
    }
  }

  /**
   * Write or update a single script
   */
  public writeScript(node: TreeNode): string | null {
    if (!this.isScriptNode(node)) {
      return null;
    }

    // Allow empty-string sources on new scripts; only skip if source is truly undefined
    if (node.source === undefined) {
      return null;
    }

    const existingMapping = this.fileMappings.get(node.guid);
    const filePath = this.getFilePath(node);
    const dirPath = path.dirname(filePath);
    const previousPath = existingMapping?.filePath;
    const pathChanged = previousPath && previousPath !== filePath;

    // Ensure directory exists
    this.ensureDirectory(dirPath);

    // Write file
    try {
      fs.writeFileSync(filePath, node.source, "utf-8");

      // If the target path changed for this guid, remove the old file to avoid stale copies
      if (pathChanged && previousPath && fs.existsSync(previousPath)) {
        // Suppress the watcher echo for our own delete so it isn't mistaken
        // for a user-initiated removal (which would delete the instance in Studio).
        this.suppressEvent(previousPath, "unlink");
        fs.unlinkSync(previousPath);
        this.pathToGuid.delete(path.resolve(previousPath));
        this.cleanupParentsIfEmpty(path.dirname(previousPath));
      }

      // Update mapping and reverse index
      this.fileMappings.set(node.guid, {
        guid: node.guid,
        filePath: filePath,
        className: node.className,
      });
      this.pathToGuid.set(path.resolve(filePath), node.guid);

      log.script(this.getRelativePath(filePath), "updated");
      return filePath;
    } catch (error) {
      log.error(`Failed to write script ${filePath}:`, error);
      return null;
    }
  }

  /**
   * Delete a script file
   */
  public deleteScript(guid: string): boolean {
    const mapping = this.fileMappings.get(guid);
    if (!mapping) {
      return false;
    }

    try {
      const deleted = this.deleteFilePathInternal(mapping.filePath);
      this.fileMappings.delete(guid);
      this.pathToGuid.delete(path.resolve(mapping.filePath));
      return deleted;
    } catch (error) {
      log.error(`Failed to delete script ${mapping.filePath}:`, error);
      return false;
    }
  }

  /**
   * Delete a script file by path even if the mapping is missing
   */
  public deleteFilePath(filePath: string): boolean {
    try {
      return this.deleteFilePathInternal(filePath);
    } catch (error) {
      log.error(`Failed to delete script ${filePath}:`, error);
      return false;
    }
  }

  /**
   * Get the filesystem path for a node
   */
  public getFilePath(node: TreeNode): string {
    return this.getFilePathWithCollisionMap(node);
  }

  /**
   * Get the filesystem path for a node, with optional collision map for batch operations
   */
  private getFilePathWithCollisionMap(
    node: TreeNode,
    batchCollisionMap?: Map<string, string>,
  ): string {
    // Build the path from the node's hierarchy. For scripts, we only use the parent path
    // as directories, then add the script file name. This prevents creating an extra
    // folder named after the script itself.
    const parts: string[] = [];

    const dirSegments = this.isScriptNode(node)
      ? node.path.slice(0, Math.max(0, node.path.length - 1))
      : node.path;

    for (const segment of dirSegments) {
      parts.push(this.sanitizeName(segment));
    }

    // If this is a script, add the script name as a file
    if (this.isScriptNode(node)) {
      const scriptName = this.getScriptFileName(node);
      parts.push(scriptName);
    }

    const desiredPath = path.join(this.baseDir, ...parts);
    const normalizedDesiredPath = path.resolve(desiredPath);

    // Check for collisions in both the persistent mappings and the batch collision map
    const existingGuid = this.findGuidByFilePath(desiredPath);
    const batchGuid = batchCollisionMap?.get(normalizedDesiredPath);
    const collision = existingGuid || batchGuid;

    // If another GUID already owns this path, disambiguate using a stable suffix
    if (collision && collision !== node.guid) {
      const uniqueName = this.getDisambiguatedScriptFileName(node);
      const uniqueParts = [...parts.slice(0, -1), uniqueName];
      return path.join(this.baseDir, ...uniqueParts);
    }

    return desiredPath;
  }

  /**
   * Get the appropriate filename for a script node
   */
  private getScriptFileName(node: TreeNode): string {
    const ext = config.scriptExtension;

    // If the script has the same name as its parent, use init pattern
    // const parentName = node.path[node.path.length - 2]; // 2 to get parent
    // if (node.name === parentName) {
    //   log.info(
    //     `Using init file pattern for script ${node.name} because it matches its parent directory name (${parentName}).`
    //   );
    //   return `init${ext}`;
    // }

    let name = this.sanitizeName(node.name);

    if (node.className === "Script") {
      name = `${name}.server`;
    } else if (node.className === "LocalScript") {
      name = `${name}.client`;
    } else if (node.className === "ModuleScript") {
      if (config.suffixModuleScripts) {
        name = `${name}.module`;
      }
    }

    return `${name}${ext}`;
  }

  /**
   * Keep Script/LocalScript suffixes when disambiguating collisions.
   */
  private getDisambiguatedScriptFileName(node: TreeNode): string {
    const baseFileName = this.getScriptFileName(node);
    const ext = config.scriptExtension;
    const guidSuffix = `__${node.guid.slice(0, 8)}`;

    if (!baseFileName.endsWith(ext)) {
      return `${baseFileName}${guidSuffix}`;
    }

    const stem = baseFileName.slice(0, -ext.length);
    const classSuffixMatch = stem.match(/(\.(?:server|client|module))$/);
    if (classSuffixMatch) {
      const classSuffix = classSuffixMatch[1];
      const rawName = stem.slice(0, -classSuffix.length);
      return `${rawName}${guidSuffix}${classSuffix}${ext}`;
    }

    return `${stem}${guidSuffix}${ext}`;
  }

  /**
   * Sanitize a name for use in filesystem
   */
  private sanitizeName(name: string): string {
    // Replace invalid filesystem characters
    return name.replace(/[<>:"|?*]/g, "_");
  }

  /**
   * Check if a node is a script
   */
  private isScriptNode(node: TreeNode): boolean {
    return (
      node.className === "Script" ||
      node.className === "LocalScript" ||
      node.className === "ModuleScript"
    );
  }

  /**
   * Ensure a directory exists
   */
  private ensureDirectory(dirPath: string): void {
    if (!fs.existsSync(dirPath)) {
      // Suppress addDir echoes for every directory this recursive mkdir creates,
      // so daemon-created folders don't loop back as user-created folders.
      if (this.eventSuppressor) {
        let current = path.resolve(dirPath);
        while (!fs.existsSync(current)) {
          this.suppressEvent(current, "addDir");
          const parent = path.dirname(current);
          if (parent === current) break;
          current = parent;
        }
      }
      fs.mkdirSync(dirPath, { recursive: true });
    }
  }

  /**
   * Internal helper to remove a file and clean mapping
   */
  private deleteFilePathInternal(filePath: string): boolean {
    const normalized = path.resolve(filePath);
    let deleted = true;

    if (fs.existsSync(normalized)) {
      try {
        this.suppressEvent(normalized, "unlink");
        fs.unlinkSync(normalized);
        log.script(this.getRelativePath(normalized), "deleted");
      } catch (error) {
        log.warn(`Failed to delete file ${filePath}:`, error);
        deleted = false;
      }
    }

    const guid = this.pathToGuid.get(normalized);
    if (guid) {
      this.fileMappings.delete(guid);
      this.pathToGuid.delete(normalized);
    }

    return deleted;
  }

  /**
   * Find the GUID that currently owns a file path, if any
   */
  private findGuidByFilePath(filePath: string): string | undefined {
    const normalized = path.resolve(filePath);
    for (const [guid, mapping] of this.fileMappings) {
      if (path.resolve(mapping.filePath) === normalized) {
        return guid;
      }
    }
    return undefined;
  }

  /**
   * Get path relative to base directory
   */
  private getRelativePath(filePath: string): string {
    return path.relative(this.baseDir, filePath);
  }

  /**
   * Get file mapping by GUID
   */
  public getMapping(guid: string): FileMapping | undefined {
    return this.fileMappings.get(guid);
  }

  /**
   * Get GUID by file path
   */
  public getGuidByPath(filePath: string): string | undefined {
    return this.pathToGuid.get(path.resolve(filePath));
  }

  /**
   * Get all file mappings
   */
  public getAllMappings(): Map<string, FileMapping> {
    return this.fileMappings;
  }

  /**
   * Get the base directory
   */
  public getBaseDir(): string {
    return this.baseDir;
  }

  /**
   * Clean up empty directories that do not correspond to active instances
   */
  public cleanupEmptyDirectories(activeFolderPaths?: Set<string>): void {
    this.cleanupEmptyDirsRecursive(this.baseDir, activeFolderPaths);
  }

  private cleanupEmptyDirsRecursive(
    dirPath: string,
    activeFolderPaths?: Set<string>,
  ): boolean {
    if (!fs.existsSync(dirPath)) {
      return false;
    }

    try {
      const entries = fs.readdirSync(dirPath, { withFileTypes: true });

      // Recursively check subdirectories
      for (const entry of entries) {
        if (entry.isDirectory()) {
          const subPath = path.join(dirPath, entry.name);
          this.cleanupEmptyDirsRecursive(subPath, activeFolderPaths);
        }
      }

      // Check if directory is now empty
      const updatedEntries = fs.readdirSync(dirPath);
      if (updatedEntries.length === 0 && dirPath !== this.baseDir) {
        if (activeFolderPaths) {
          const relPath = path
            .relative(this.baseDir, dirPath)
            .replace(/\\/g, "/");
          if (activeFolderPaths.has(relPath)) {
            return false; // Preserve folder instance in Roblox DataModel
          }
        }

        try {
          this.suppressEvent(dirPath, "unlinkDir");
          fs.rmdirSync(dirPath);
          return true;
        } catch {
          return false;
        }
      }
    } catch {
      // Ignore read errors
    }

    return false;
  }

  /**
   * Walk up from a directory and remove empty parents until baseDir is reached.
   */
  private cleanupParentsIfEmpty(startDir: string): void {
    let current = path.resolve(startDir);
    const root = this.baseDir;

    while (current.startsWith(root)) {
      if (current === root) {
        break;
      }

      try {
        const entries = fs.existsSync(current)
          ? fs.readdirSync(current, { withFileTypes: true })
          : [];

        if (entries.length === 0) {
          this.suppressEvent(current, "unlinkDir");
          fs.rmdirSync(current);
          current = path.dirname(current);
        } else {
          break;
        }
      } catch {
        break;
      }
    }
  }
}
