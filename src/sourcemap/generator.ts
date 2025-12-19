import * as fs from "fs";
import * as path from "path";
import { TreeNode } from "../fs/treeManager.js";
import { FileMapping } from "../fs/fileWriter.js";
import { log } from "../util/log.js";

/**
 * Rojo-compatible sourcemap tree structure
 */
interface SourcemapNode {
  name: string;
  className: string;
  filePaths?: string[];
  children?: SourcemapNode[];
}

interface SourcemapRoot {
  name: string;
  className: string;
  children: SourcemapNode[];
}

/**
 * Generates Rojo-compatible sourcemap.json for luau-lsp
 */
export class SourcemapGenerator {
  constructor() {}

  /**
   * Incrementally upsert a subtree into the sourcemap, optionally removing the old path first.
   * Falls back to full regeneration if anything goes wrong.
   */
  public upsertSubtree(
    node: TreeNode,
    allNodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>,
    outputPath: string,
    oldPath?: string[]
  ): void {
    try {
      const sourcemap = this.readOrCreateRoot(outputPath);

      // If the node moved/renamed, prune the previous location
      if (oldPath && !this.pathsMatch(oldPath, node.path)) {
        this.removePath(sourcemap, oldPath);
      }

      const newSubtree = this.buildNodeFromTree(node, fileMappings);
      this.insertNodeAtPath(sourcemap, newSubtree, node.path, allNodes);
      this.write(sourcemap, outputPath);
    } catch (error) {
      log.warn("Incremental sourcemap update failed, regenerating:", error);
      this.generateAndWrite(allNodes, fileMappings, outputPath);
    }
  }

  /**
   * Generate complete sourcemap from tree and file mappings
   */
  public generate(
    nodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>
  ): SourcemapRoot {
    log.info("Generating sourcemap...");
    log.debug(
      `Total nodes: ${nodes.size}, File mappings: ${fileMappings.size}`
    );

    // Build a parent->children index to avoid O(n^2) scans
    const childrenByParent = new Map<string, TreeNode[]>();
    const serviceRoots: TreeNode[] = [];

    for (const node of nodes.values()) {
      if (node.path.length === 0) continue; // Skip DataModel root

      if (node.path.length === 1) {
        serviceRoots.push(node);
      }

      const parentKey = this.keyFromPath(node.path.slice(0, -1));
      if (!childrenByParent.has(parentKey)) {
        childrenByParent.set(parentKey, []);
      }
      childrenByParent.get(parentKey)!.push(node);
    }

    log.debug(`Service groups: ${serviceRoots.length}`);

    const children: SourcemapNode[] = [];
    for (const serviceNode of serviceRoots) {
      const serviceName = serviceNode.name;
      const direct = childrenByParent.get(this.keyFromPath([serviceName]));
      const groupSize = direct ? direct.length : 0;
      log.debug(
        `Building service: ${serviceName} (${groupSize} direct children)`
      );

      const built = this.buildNodeFromIndex(
        serviceNode,
        childrenByParent,
        fileMappings,
        new Set()
      );

      if (built) {
        children.push(built);
        log.debug(`Added service node: ${serviceName}`);
      }
    }

    const sourcemap: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children,
    };

    log.success(`Sourcemap generated with ${children.length} root services`);
    return sourcemap;
  }

  /**
   * Write sourcemap to file
   */
  public write(
    sourcemap: SourcemapRoot,
    outputPath: string = "sourcemap.json"
  ): void {
    try {
      // Ensure destination directory exists
      const dir = path.dirname(outputPath);
      if (dir && dir !== "." && !fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const json = JSON.stringify(sourcemap, null, 2);
      fs.writeFileSync(outputPath, json, "utf-8");
      log.success(`Sourcemap written to: ${outputPath}`);
    } catch (error) {
      log.error("Failed to write sourcemap:", error);
    }
  }

  /**
   * Check if two paths match
   */
  private pathsMatch(path1: string[], path2: string[]): boolean {
    if (path1.length !== path2.length) return false;
    return path1.every((segment, i) => segment === path2[i]);
  }

  /**
   * Build node hierarchy using an index map (fast path for full generation).
   */
  private buildNodeFromIndex(
    node: TreeNode,
    childrenByParent: Map<string, TreeNode[]>,
    fileMappings: Map<string, FileMapping>,
    visited: Set<string>,
    cwd = process.cwd() // compute once
  ): SourcemapNode | null {
    const nodeKey = this.keyFromPath(node.path);

    if (visited.has(nodeKey)) {
      log.debug(
        `Detected cyclic path in sourcemap generation: ${node.path.join("/")}`
      );
      return null;
    }
    visited.add(nodeKey);

    const result: SourcemapNode = {
      name: node.name,
      className: node.className,
    };

    const mapping = fileMappings.get(node.guid);
    if (mapping) {
      const rel = path.relative(cwd, mapping.filePath).replace(/\\/g, "/");
      result.filePaths = [rel];
    }

    const childNodes = childrenByParent.get(nodeKey);
    if (childNodes) {
      const children: SourcemapNode[] = [];

      for (const child of childNodes) {
        const built = this.buildNodeFromIndex(
          child,
          childrenByParent,
          fileMappings,
          visited,
          cwd
        );
        if (built) children.push(built);
      }

      if (children.length > 0) {
        result.children = children;
      }
    }

    return result;
  }

  private keyFromPath(pathSegments: string[]): string {
    return pathSegments.join("\u0001");
  }

  /**
   * Build a SourcemapNode from a TreeNode, recursively including children.
   */
  private buildNodeFromTree(
    node: TreeNode,
    fileMappings: Map<string, FileMapping>
  ): SourcemapNode {
    const result: SourcemapNode = {
      name: node.name,
      className: node.className,
    };

    const mapping = fileMappings.get(node.guid);
    if (mapping) {
      const relativePath = path.relative(process.cwd(), mapping.filePath);
      result.filePaths = [relativePath.replace(/\\/g, "/")];
    }

    const children: SourcemapNode[] = [];
    for (const child of node.children.values()) {
      children.push(this.buildNodeFromTree(child, fileMappings));
    }

    if (children.length > 0) {
      result.children = children;
    }

    return result;
  }

  /**
   * Read an existing sourcemap or create a new root.
   */
  private readOrCreateRoot(outputPath: string): SourcemapRoot {
    if (fs.existsSync(outputPath)) {
      try {
        const raw = fs.readFileSync(outputPath, "utf-8");
        return JSON.parse(raw) as SourcemapRoot;
      } catch (error) {
        log.warn("Failed to read existing sourcemap, recreating:", error);
      }
    }

    return {
      name: "Game",
      className: "DataModel",
      children: [],
    };
  }

  /**
   * Insert or replace a subtree at the given path, creating intermediate parents as needed.
   */
  private insertNodeAtPath(
    root: SourcemapRoot,
    newNode: SourcemapNode,
    pathSegments: string[],
    allNodes: Map<string, TreeNode>
  ): void {
    if (pathSegments.length === 0) return;

    let currentChildren = root.children;

    for (let i = 0; i < pathSegments.length; i++) {
      const segment = pathSegments[i];
      let existingIndex = currentChildren.findIndex((n) => n.name === segment);

      if (i === pathSegments.length - 1) {
        if (existingIndex !== -1) {
          currentChildren.splice(existingIndex, 1, newNode);
        } else {
          currentChildren.push(newNode);
        }
        return;
      }

      if (existingIndex === -1) {
        const ancestorNode = this.findNodeByPath(
          allNodes,
          pathSegments.slice(0, i + 1)
        );
        const className = ancestorNode?.className ?? "Folder";
        const placeholder: SourcemapNode = {
          name: segment,
          className,
          children: [],
        };
        currentChildren.push(placeholder);
        existingIndex = currentChildren.length - 1;
      }

      const holder = currentChildren[existingIndex];
      if (!holder.children) {
        holder.children = [];
      }

      currentChildren = holder.children;
    }
  }

  private findNodeByPath(
    nodes: Map<string, TreeNode>,
    pathSegments: string[]
  ): TreeNode | undefined {
    for (const node of nodes.values()) {
      if (this.pathsMatch(node.path, pathSegments)) {
        return node;
      }
    }
    return undefined;
  }

  /**
   * Generate and write sourcemap in one call
   */
  public generateAndWrite(
    nodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>,
    outputPath: string = "sourcemap.json"
  ): void {
    const sourcemap = this.generate(nodes, fileMappings);
    this.write(sourcemap, outputPath);
  }

  /**
   * Remove a node (and now-empty ancestors) from an existing sourcemap file by path.
   * Falls back to full regeneration if the file is missing or malformed.
   */
  public prunePath(
    pathSegments: string[],
    outputPath: string,
    nodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>
  ): boolean {
    try {
      if (!fs.existsSync(outputPath)) {
        this.generateAndWrite(nodes, fileMappings, outputPath);
        return true;
      }

      const raw = fs.readFileSync(outputPath, "utf-8");
      const json = JSON.parse(raw) as SourcemapRoot;

      const removed = this.removePath(json, pathSegments);
      if (removed) {
        this.write(json, outputPath);
      }
      return removed;
    } catch (error) {
      log.warn("Prune failed, regenerating sourcemap:", error);
      this.generateAndWrite(nodes, fileMappings, outputPath);
      return true;
    }
  }

  /**
   * Remove node matching path; prune empty parents.
   */
  private removePath(root: SourcemapRoot, pathSegments: string[]): boolean {
    if (pathSegments.length === 0) return false;

    const pruneRecursive = (
      nodes: SourcemapNode[] | undefined,
      idx: number
    ): boolean => {
      if (!nodes) return false;
      const name = pathSegments[idx];
      const nodeIndex = nodes.findIndex((n) => n.name === name);
      if (nodeIndex === -1) return false;

      const node = nodes[nodeIndex];

      if (idx === pathSegments.length - 1) {
        // Remove the entire subtree
        nodes.splice(nodeIndex, 1);
        return true;
      }

      const removed = pruneRecursive(node.children, idx + 1);

      // Clean up empty child containers
      if (
        removed &&
        node.children &&
        node.children.length === 0 &&
        !node.filePaths
      ) {
        nodes.splice(nodeIndex, 1);
      }

      return removed;
    };

    return pruneRecursive(root.children, 0);
  }

  /**
   * Validate that all paths in sourcemap point to existing files
   */
  public validate(sourcemap: SourcemapRoot): {
    valid: boolean;
    errors: string[];
  } {
    const errors: string[] = [];

    const checkNode = (node: SourcemapNode) => {
      if (node.filePaths) {
        for (const filePath of node.filePaths) {
          const fullPath = path.resolve(process.cwd(), filePath);
          if (!fs.existsSync(fullPath)) {
            errors.push(`Missing file: ${filePath}`);
          }
        }
      }

      if (node.children) {
        for (const child of node.children) {
          checkNode(child);
        }
      }
    };

    for (const child of sourcemap.children) {
      checkNode(child);
    }

    return {
      valid: errors.length === 0,
      errors,
    };
  }
}
