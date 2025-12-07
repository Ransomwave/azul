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

    // Build hierarchy starting from DataModel root
    const children: SourcemapNode[] = [];

    // Group nodes by root service
    const serviceGroups = this.groupByRootService(nodes);
    log.debug(`Service groups: ${serviceGroups.size}`);

    // Build tree for each service
    for (const [serviceName, serviceNodes] of serviceGroups) {
      log.debug(
        `Building service: ${serviceName} (${serviceNodes.length} nodes)`
      );
      const serviceNode = this.buildServiceNode(
        serviceName,
        serviceNodes,
        fileMappings
      );
      if (serviceNode) {
        children.push(serviceNode);
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
   * Group nodes by their root service
   */
  private groupByRootService(
    nodes: Map<string, TreeNode>
  ): Map<string, TreeNode[]> {
    const groups = new Map<string, TreeNode[]>();

    for (const node of nodes.values()) {
      if (node.path.length === 0) continue; // Skip root

      const serviceName = node.path[0];
      if (!groups.has(serviceName)) {
        groups.set(serviceName, []);
      }
      groups.get(serviceName)!.push(node);
    }

    return groups;
  }

  /**
   * Build node structure for a service
   */
  private buildServiceNode(
    serviceName: string,
    nodes: TreeNode[],
    fileMappings: Map<string, FileMapping>
  ): SourcemapNode | null {
    // Find the service node itself
    const serviceNode = nodes.find((n) => n.path.length === 1);
    if (!serviceNode) return null;

    const result: SourcemapNode = {
      name: serviceName,
      className: serviceNode.className,
    };

    // Build children hierarchy
    const children = this.buildChildrenNodes(nodes, fileMappings, [
      serviceName,
    ]);
    if (children.length > 0) {
      result.children = children;
    }

    return result;
  }

  /**
   * Build children nodes for a given parent path
   */
  private buildChildrenNodes(
    allNodes: TreeNode[],
    fileMappings: Map<string, FileMapping>,
    parentPath: string[]
  ): SourcemapNode[] {
    const children: SourcemapNode[] = [];

    // Find direct children of this path
    const directChildren = allNodes.filter(
      (node) =>
        node.path.length === parentPath.length + 1 &&
        this.pathsMatch(node.path.slice(0, parentPath.length), parentPath)
    );

    for (const childNode of directChildren) {
      const node: SourcemapNode = {
        name: childNode.name,
        className: childNode.className,
      };

      // Add file path if this is a script
      const mapping = fileMappings.get(childNode.guid);
      if (mapping) {
        const relativePath = path.relative(process.cwd(), mapping.filePath);
        node.filePaths = [relativePath.replace(/\\/g, "/")];
      }

      // Recursively build children
      const grandChildren = this.buildChildrenNodes(
        allNodes,
        fileMappings,
        childNode.path
      );
      if (grandChildren.length > 0) {
        node.children = grandChildren;
      }

      children.push(node);
    }

    return children;
  }

  /**
   * Check if two paths match
   */
  private pathsMatch(path1: string[], path2: string[]): boolean {
    if (path1.length !== path2.length) return false;
    return path1.every((segment, i) => segment === path2[i]);
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
