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

    const filePath = this.getFilePath(node);
    const dirPath = path.dirname(filePath);

    // Ensure directory exists
    this.ensureDirectory(dirPath);

    // Write file
    try {
      fs.writeFileSync(filePath, node.source, "utf-8");

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
      if (fs.existsSync(mapping.filePath)) {
        fs.unlinkSync(mapping.filePath);
        log.script(this.getRelativePath(mapping.filePath), "deleted");
      }
      this.fileMappings.delete(guid);
      return true;
    } catch (error) {
      log.error(`Failed to delete script ${mapping.filePath}:`, error);
      return false;
    }
  }

  /**
   * Get the filesystem path for a node
   */
  public getFilePath(node: TreeNode): string {
    // Build the path from the node's hierarchy
    const parts: string[] = [];

    // Add all path segments except the root service if it's excluded
    for (let i = 0; i < node.path.length; i++) {
      const segment = node.path[i];

      // Sanitize the name for filesystem
      const sanitized = this.sanitizeName(segment);
      parts.push(sanitized);
    }

    // If this is a script, add the script name as a file
    if (this.isScriptNode(node)) {
      // Check if we need to use init file pattern
      const scriptName = this.getScriptFileName(node);
      parts.push(scriptName);
    }

    return path.join(this.baseDir, ...parts);
  }

  /**
   * Get the appropriate filename for a script node
   */
  private getScriptFileName(node: TreeNode): string {
    const ext = config.scriptExtension;

    // If the script has the same name as its parent, use init pattern
    const parentName = node.path[node.path.length - 1];
    if (node.name === parentName) {
      return `init${ext}`;
    }

    return `${this.sanitizeName(node.name)}${ext}`;
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
    if (!fs.existsSync(dirPath) || dirPath === this.baseDir) {
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
    if (updatedEntries.length === 0) {
      fs.rmdirSync(dirPath);
      return true;
    }

    return false;
  }
}
