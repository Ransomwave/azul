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
  guid?: string;
  filePaths?: string[];
  children?: SourcemapNode[];
}

interface SourcemapRoot {
  name: string;
  className: string;
  children: SourcemapNode[];
  _azul?: Record<string, unknown>;
}

/**
 * Generates Rojo-compatible sourcemap.json for luau-lsp
 */
export class SourcemapGenerator {
  private placeId?: number;

  constructor() {}

  /**
   * Record the Studio place so every subsequent write stamps `_azul.placeId`,
   * which is what `azul open-studio` reads back.
   */
  public setPlaceId(placeId?: number): void {
    // 0 means the place was never saved to Roblox, so there is nothing to open.
    // if there is no placeId, set it to undefined so we don't accidentally keep an old value.
    this.placeId = placeId && placeId > 0 ? placeId : undefined;
  }

  private sortTreeNodes(nodes: Iterable<TreeNode>): TreeNode[] {
    return Array.from(nodes).sort((a, b) => {
      const nameCompare = a.name.localeCompare(b.name);
      if (nameCompare !== 0) return nameCompare;

      const classCompare = a.className.localeCompare(b.className);
      if (classCompare !== 0) return classCompare;

      return a.guid.localeCompare(b.guid);
    });
  }

  private findRootNode(nodes: Map<string, TreeNode>): TreeNode | null {
    const root = nodes.get("root");
    if (root) {
      return root;
    }

    for (const node of nodes.values()) {
      if (node.path.length === 0 && node.className === "DataModel") {
        return node;
      }
    }

    return null;
  }

  /**
   * Generate complete sourcemap from tree and file mappings
   */
  public generate(
    nodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>,
  ): SourcemapRoot {
    log.debug("Generating sourcemap...");
    log.debug(
      `Total nodes: ${nodes.size}, File mappings: ${fileMappings.size}`,
    );

    const rootNode = this.findRootNode(nodes);
    const serviceNodes = rootNode
      ? this.sortTreeNodes(rootNode.children.values())
      : this.sortTreeNodes(
          Array.from(nodes.values()).filter((node) => node.path.length === 1),
        );

    const visited = new Set<string>();
    const children: SourcemapNode[] = [];

    for (const serviceNode of serviceNodes) {
      const built = this.buildNodeFromTree(
        serviceNode,
        fileMappings,
        visited,
        process.cwd(),
      );
      if (built) {
        children.push(built);
      }
    }

    const sourcemap: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children,
    };

    log.debug(`Sourcemap generated with ${children.length} root services`);
    return sourcemap;
  }

  /**
   * Write sourcemap to file
   */
  public write(
    sourcemap: SourcemapRoot,
    outputPath: string = "sourcemap.json",
  ): void {
    try {
      if (this.placeId) {
        sourcemap._azul = { ...sourcemap._azul, placeId: this.placeId };
      }

      // Ensure destination directory exists
      const dir = path.dirname(outputPath);
      if (dir && dir !== "." && !fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const json = JSON.stringify(sourcemap, null, 2);

      // Skip identical writes so luau-lsp isn't triggered to reindex for nothing
      if (
        fs.existsSync(outputPath) &&
        fs.readFileSync(outputPath, "utf-8") === json
      ) {
        return;
      }

      fs.writeFileSync(outputPath, json, "utf-8");
      log.debug(`Sourcemap written to: ${outputPath}`);
    } catch (error) {
      log.error("Failed to write sourcemap:", error);
    }
  }

  /**
   * Build a SourcemapNode from a TreeNode, recursively including children.
   */
  private buildNodeFromTree(
    node: TreeNode,
    fileMappings: Map<string, FileMapping>,
    visited: Set<string> = new Set(),
    cwd = process.cwd(),
  ): SourcemapNode | null {
    if (visited.has(node.guid)) {
      log.debug(
        `Detected cyclic path in sourcemap generation: ${node.path.join("/")}`,
      );
      return null;
    }
    visited.add(node.guid);

    const result: SourcemapNode = {
      name: node.name,
      className: node.className,
      guid: node.guid,
    };

    const mapping = fileMappings.get(node.guid);
    if (mapping) {
      const relativePath = path.relative(cwd, mapping.filePath);
      result.filePaths = [relativePath.replace(/\\/g, "/")];
    }

    const sortedChildren = this.sortTreeNodes(node.children.values());
    const children: SourcemapNode[] = [];
    for (const child of sortedChildren) {
      const built = this.buildNodeFromTree(child, fileMappings, visited, cwd);
      if (built) {
        children.push(built);
      }
    }

    if (children.length > 0) {
      result.children = children;
    }

    return result;
  }

  /**
   * Generate and write sourcemap in one call
   */
  public generateAndWrite(
    nodes: Map<string, TreeNode>,
    fileMappings: Map<string, FileMapping>,
    outputPath: string = "sourcemap.json",
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
