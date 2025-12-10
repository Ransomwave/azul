import * as fs from "fs";
import * as path from "path";
import { TreeNode } from "./treeManager.js";
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

  constructor(baseDir: string = config.syncDir) {
    this.baseDir = path.resolve(baseDir);
    this.ensureDirectory(this.baseDir);
  }

  /**
   * Write all script nodes to the filesystem
   */
  public writeTree(nodes: Map<string, TreeNode>): void {
    log.info("Writing tree to filesystem...");

    // Clear existing mappings
    this.fileMappings.clear();

    // Process all script nodes
    for (const node of nodes.values()) {
      if (this.isScriptNode(node)) {
        this.writeScript(node);
      }
    }

    log.success(`Wrote ${this.fileMappings.size} scripts to filesystem`);
  }

  /**
   * Write or update a single script
   */
  public writeScript(node: TreeNode): string | null {
    if (!this.isScriptNode(node) || !node.source) {
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
        fs.unlinkSync(previousPath);
        this.cleanupParentsIfEmpty(path.dirname(previousPath));
      }

      // Update mapping
      this.fileMappings.set(node.guid, {
        guid: node.guid,
        filePath: filePath,
        className: node.className,
      });

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

    // If another GUID already owns this path, disambiguate using a stable suffix
    const collision = this.findGuidByFilePath(desiredPath);
    if (collision && collision !== node.guid) {
      const ext = config.scriptExtension;
      const uniqueName = `${this.sanitizeName(node.name)}__${node.guid.slice(
        0,
        8
      )}${ext}`;
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
      name = `${name}.module`;
    }

    return `${name}${ext}`;
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
      fs.mkdirSync(dirPath, { recursive: true });
    }
  }

  /**
   * Internal helper to remove a file and clean mapping
   */
  private deleteFilePathInternal(filePath: string): boolean {
    const normalized = path.resolve(filePath);

    if (fs.existsSync(normalized)) {
      fs.unlinkSync(normalized);
      log.script(this.getRelativePath(normalized), "deleted");
    }

    for (const [guid, mapping] of this.fileMappings) {
      if (path.resolve(mapping.filePath) === normalized) {
        this.fileMappings.delete(guid);
        break;
      }
    }

    return true;
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
    const normalizedPath = path.resolve(filePath);
    for (const [guid, mapping] of this.fileMappings) {
      if (path.resolve(mapping.filePath) === normalizedPath) {
        return guid;
      }
    }
    return undefined;
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
   * Clean up empty directories
   */
  public cleanupEmptyDirectories(): void {
    this.cleanupEmptyDirsRecursive(this.baseDir);
  }

  private cleanupEmptyDirsRecursive(dirPath: string): boolean {
    if (!fs.existsSync(dirPath)) {
      return false;
    }

    const entries = fs.readdirSync(dirPath, { withFileTypes: true });

    // Recursively check subdirectories
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const subPath = path.join(dirPath, entry.name);
        this.cleanupEmptyDirsRecursive(subPath);
      }
    }

    // Check if directory is now empty
    const updatedEntries = fs.readdirSync(dirPath);
    if (updatedEntries.length === 0 && dirPath !== this.baseDir) {
      fs.rmdirSync(dirPath);
      return true;
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

      const entries = fs.existsSync(current)
        ? fs.readdirSync(current, { withFileTypes: true })
        : [];

      if (entries.length === 0) {
        fs.rmdirSync(current);
        current = path.dirname(current);
      } else {
        break;
      }
    }
  }
}
