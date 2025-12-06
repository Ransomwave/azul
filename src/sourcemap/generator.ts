import * as fs from "fs";
import * as path from "path";
import { TreeNode } from "../fs/treeManager.js";
import { FileMapping } from "../fs/fileWriter.js";
import { log } from "../util/log.js";

/**
 * Rojo-compatible sourcemap tree structure
 */
interface SourcemapTree {
  [key: string]: SourcemapNode | string;
}

interface SourcemapNode {
  $className?: string;
  $path?: string;
  [key: string]: any;
}

interface SourcemapRoot {
  name: string;
  tree: SourcemapTree;
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

    const tree: SourcemapTree = {};

    // Group nodes by root service
    const serviceGroups = this.groupByRootService(nodes);

    // Build tree for each service
    for (const [serviceName, serviceNodes] of serviceGroups) {
      const serviceTree = this.buildServiceTree(serviceNodes, fileMappings);
      if (Object.keys(serviceTree).length > 0) {
        tree[serviceName] = serviceTree;
      }
    }

    const sourcemap: SourcemapRoot = {
      name: "super-studio-sync",
      tree,
    };

    log.success(
      `Sourcemap generated with ${Object.keys(tree).length} root services`
    );
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
   * Build tree structure for a service
   */
  private buildServiceTree(
    nodes: TreeNode[],
    fileMappings: Map<string, FileMapping>
  ): SourcemapNode {
    const root: SourcemapNode = {};

    // Find the service node itself
    const serviceNode = nodes.find((n) => n.path.length === 1);
    if (serviceNode) {
      root.$className = serviceNode.className;
    }

    // Build hierarchy
    for (const node of nodes) {
      if (node.path.length <= 1) continue; // Skip service itself

      this.insertNode(root, node, fileMappings);
    }

    return root;
  }

  /**
   * Insert a node into the tree structure
   */
  private insertNode(
    root: SourcemapNode,
    node: TreeNode,
    fileMappings: Map<string, FileMapping>
  ): void {
    // Navigate to the correct position in the tree
    let current = root;

    // Skip the first element (service name) and navigate through the path
    for (let i = 1; i < node.path.length - 1; i++) {
      const segment = node.path[i];

      if (!current[segment]) {
        current[segment] = {};
      }

      if (typeof current[segment] === "object") {
        current = current[segment] as SourcemapNode;
      }
    }

    // Add the final node
    const nodeName = node.name;
    const nodeData: SourcemapNode = {
      $className: node.className,
    };

    // If this node has a file mapping, add the path
    const mapping = fileMappings.get(node.guid);
    if (mapping) {
      const relativePath = path.relative(process.cwd(), mapping.filePath);
      nodeData.$path = relativePath.replace(/\\/g, "/"); // Convert to forward slashes
    }

    current[nodeName] = nodeData;

    // If the node has children that aren't scripts, we need to add them as sub-properties
    // This is handled by subsequent calls to insertNode
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

    const checkNode = (node: any, nodePath: string) => {
      if (typeof node !== "object" || node === null) return;

      if (node.$path) {
        const fullPath = path.resolve(process.cwd(), node.$path);
        if (!fs.existsSync(fullPath)) {
          errors.push(`Missing file: ${node.$path}`);
        }
      }

      for (const [key, value] of Object.entries(node)) {
        if (!key.startsWith("$")) {
          checkNode(value, `${nodePath}.${key}`);
        }
      }
    };

    checkNode(sourcemap.tree, "tree");

    return {
      valid: errors.length === 0,
      errors,
    };
  }
}
