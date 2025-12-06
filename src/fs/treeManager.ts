import { InstanceData } from "../ipc/messages.js";
import { log } from "../util/log.js";

/**
 * Represents a node in the virtual DataModel tree
 */
export interface TreeNode {
  guid: string;
  className: string;
  name: string;
  path: string[];
  source?: string;
  children: Map<string, TreeNode>;
  parent?: TreeNode;
}

/**
 * Manages the in-memory representation of Studio's DataModel
 */
export class TreeManager {
  private nodes: Map<string, TreeNode> = new Map();
  private root: TreeNode | null = null;

  /**
   * Process a full snapshot from Studio
   */
  public applyFullSnapshot(instances: InstanceData[]): void {
    log.info(`Processing full snapshot: ${instances.length} instances`);

    // Clear existing tree
    this.nodes.clear();
    this.root = null;

    // First pass: create all nodes
    for (const instance of instances) {
      const node: TreeNode = {
        guid: instance.guid,
        className: instance.className,
        name: instance.name,
        path: instance.path,
        source: instance.source,
        children: new Map(),
      };
      this.nodes.set(instance.guid, node);
    }

    // Second pass: build hierarchy
    for (const instance of instances) {
      const node = this.nodes.get(instance.guid);
      if (!node) continue;

      if (instance.path.length === 1) {
        // This is a root service
        if (!this.root) {
          this.root = {
            guid: "root",
            className: "DataModel",
            name: "game",
            path: [],
            children: new Map(),
          };
          this.nodes.set("root", this.root);
        }
        this.root.children.set(node.guid, node);
        node.parent = this.root;
      } else {
        // Find parent by matching path
        const parentPath = instance.path.slice(0, -1);
        const parent = this.findNodeByPath(parentPath);
        if (parent) {
          parent.children.set(node.guid, node);
          node.parent = parent;
        } else {
          log.warn(`Parent not found for ${instance.path.join("/")}`);
        }
      }
    }

    log.success(`Tree built: ${this.nodes.size} nodes`);
  }

  /**
   * Update a single instance
   */
  public updateInstance(instance: InstanceData): void {
    const existing = this.nodes.get(instance.guid);

    if (existing) {
      // Update existing node
      const pathChanged =
        JSON.stringify(existing.path) !== JSON.stringify(instance.path);
      const nameChanged = existing.name !== instance.name;

      existing.className = instance.className;
      existing.name = instance.name;
      existing.path = instance.path;
      existing.source = instance.source;

      if (pathChanged || nameChanged) {
        // Need to re-parent
        this.reparentNode(existing, instance.path);
      }

      log.debug(`Updated instance: ${instance.path.join("/")}`);
    } else {
      // Create new node
      const node: TreeNode = {
        guid: instance.guid,
        className: instance.className,
        name: instance.name,
        path: instance.path,
        source: instance.source,
        children: new Map(),
      };

      this.nodes.set(instance.guid, node);
      this.reparentNode(node, instance.path);

      log.debug(`Created instance: ${instance.path.join("/")}`);
    }
  }

  /**
   * Delete an instance by GUID
   */
  public deleteInstance(guid: string): TreeNode | null {
    const node = this.nodes.get(guid);
    if (!node) {
      log.warn(`Attempted to delete non-existent node: ${guid}`);
      return null;
    }

    // Remove from parent
    if (node.parent) {
      node.parent.children.delete(guid);
    }

    // Remove from index
    this.nodes.delete(guid);

    // Recursively delete children
    for (const child of node.children.values()) {
      this.deleteInstance(child.guid);
    }

    log.debug(`Deleted instance: ${node.path.join("/")}`);
    return node;
  }

  /**
   * Update script source only
   */
  public updateScriptSource(guid: string, source: string): void {
    const node = this.nodes.get(guid);
    if (node) {
      node.source = source;
      log.debug(`Updated script source: ${node.path.join("/")}`);
    } else {
      log.warn(`Script not found for GUID: ${guid}`);
    }
  }

  /**
   * Get a node by GUID
   */
  public getNode(guid: string): TreeNode | undefined {
    return this.nodes.get(guid);
  }

  /**
   * Get all nodes
   */
  public getAllNodes(): Map<string, TreeNode> {
    return this.nodes;
  }

  /**
   * Get all script nodes
   */
  public getScriptNodes(): TreeNode[] {
    return Array.from(this.nodes.values()).filter(
      (node) =>
        node.className === "Script" ||
        node.className === "LocalScript" ||
        node.className === "ModuleScript"
    );
  }

  /**
   * Find a node by its path
   */
  private findNodeByPath(path: string[]): TreeNode | undefined {
    for (const node of this.nodes.values()) {
      if (JSON.stringify(node.path) === JSON.stringify(path)) {
        return node;
      }
    }
    return undefined;
  }

  /**
   * Re-parent a node based on its path
   */
  private reparentNode(node: TreeNode, path: string[]): void {
    // Remove from old parent
    if (node.parent) {
      node.parent.children.delete(node.guid);
    }

    // Find new parent
    if (path.length === 1) {
      // Root service
      if (!this.root) {
        this.root = {
          guid: "root",
          className: "DataModel",
          name: "game",
          path: [],
          children: new Map(),
        };
        this.nodes.set("root", this.root);
      }
      this.root.children.set(node.guid, node);
      node.parent = this.root;
    } else {
      const parentPath = path.slice(0, -1);
      const parent = this.findNodeByPath(parentPath);
      if (parent) {
        parent.children.set(node.guid, node);
        node.parent = parent;
      } else {
        log.warn(`Parent not found for re-parenting: ${path.join("/")}`);
      }
    }
  }

  /**
   * Get tree statistics
   */
  public getStats(): {
    totalNodes: number;
    scriptNodes: number;
    maxDepth: number;
  } {
    const scripts = this.getScriptNodes();
    const maxDepth = Math.max(
      ...Array.from(this.nodes.values()).map((n) => n.path.length),
      0
    );

    return {
      totalNodes: this.nodes.size,
      scriptNodes: scripts.length,
      maxDepth,
    };
  }
}
