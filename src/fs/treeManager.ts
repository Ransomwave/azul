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
  private pathIndex: Map<string, TreeNode> = new Map(); // pathKey → TreeNode
  private root: TreeNode | null = null;

  private pathKey(path: string[]): string {
    return path.join("\u0000");
  }

  private registerSubtree(node: TreeNode): void {
    this.pathIndex.set(this.pathKey(node.path), node);
    for (const child of node.children.values()) {
      this.registerSubtree(child);
    }
  }

  private unregisterSubtree(node: TreeNode): void {
    this.pathIndex.delete(this.pathKey(node.path));
    for (const child of node.children.values()) {
      this.unregisterSubtree(child);
    }
  }

  public updateInstance(instance: InstanceData): {
    node: TreeNode;
    pathChanged: boolean;
    nameChanged: boolean;
    isNew: boolean;
    prevPath?: string[];
    prevName?: string;
  } | null {
    const existing = this.nodes.get(instance.guid);

    if (existing) {
      const prevPath = [...existing.path];
      const prevName = existing.name;
      const pathChanged = !this.pathsEqual(existing.path, instance.path);
      const nameChanged = existing.name !== instance.name;

      const nextSource =
        instance.source !== undefined ? instance.source : existing.source;

      if (pathChanged) {
        this.unregisterSubtree(existing);
      }

      existing.className = instance.className;
      existing.name = instance.name;
      existing.path = instance.path;
      existing.source = nextSource;

      if (pathChanged || nameChanged) {
        this.reparentNode(existing, instance.path);
        this.recalculateChildPaths(existing);
        this.registerSubtree(existing);
      }

      log.script(`Updated instance: ${instance.path.join("/")}`, "updated");
      return {
        node: existing,
        pathChanged,
        nameChanged,
        isNew: false,
        prevPath,
        prevName,
      };
    }

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
    this.recalculateChildPaths(node);
    this.registerSubtree(node);

    log.script(`Created instance: ${instance.path.join("/")}`, "created");
    return { node, pathChanged: false, nameChanged: false, isNew: true };
  }

  /**
   * Process a full snapshot from Studio
   */
  public applyFullSnapshot(instances: InstanceData[]): void {
    log.info(`Processing full snapshot: ${instances.length} instances`);

    // Clear existing tree
    this.nodes.clear();
    this.pathIndex.clear();
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
      this.pathIndex.set(this.pathKey(instance.path), node);
      log.debug(`Created node: ${instance.path.join("/")}`);
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
        log.debug(`Assigned root parent for: ${instance.path.join("/")}`);
      } else {
        // Find parent by matching path
        const parentPath = instance.path.slice(0, -1);
        const parent = this.findNodeByPath(parentPath);
        if (parent) {
          parent.children.set(node.guid, node);
          node.parent = parent;
          log.debug(`Assigned parent for: ${instance.path.join("/")}`);
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
  private recalculateChildPaths(node: TreeNode): void {
    for (const child of node.children.values()) {
      child.path = [...node.path, child.name];
      this.recalculateChildPaths(child);
    }
  }

  public getDescendantScripts(guid: string): TreeNode[] {
    const start = this.nodes.get(guid);
    if (!start) {
      return [];
    }

    const scripts: TreeNode[] = [];
    const walk = (node: TreeNode): void => {
      for (const child of node.children.values()) {
        if (this.isScriptNode(child)) {
          scripts.push(child);
        }
        walk(child);
      }
    };

    walk(start);
    return scripts;
  }

  private isScriptNode(node: TreeNode): boolean {
    return (
      node.className === "Script" ||
      node.className === "LocalScript" ||
      node.className === "ModuleScript"
    );
  }

  private pathsEqual(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    return a.every((segment, idx) => segment === b[idx]);
  }

  /**
   * Delete an instance by GUID
   */
  public deleteInstance(guid: string): TreeNode | null {
    const node = this.nodes.get(guid);
    if (!node) {
      log.debug(`Delete ignored for missing node: ${guid}`);
      return null;
    }

    // Detach from parent first so no one references this subtree
    if (node.parent) {
      node.parent.children.delete(guid);
    }

    // Iterative delete to avoid repeated recursion work on large subtrees
    const stack: TreeNode[] = [node];
    while (stack.length > 0) {
      const current = stack.pop()!;
      for (const child of current.children.values()) {
        stack.push(child);
      }

      this.pathIndex.delete(this.pathKey(current.path));
      this.nodes.delete(current.guid);

      // Break references to help GC and prevent accidental reuse
      current.children.clear();
      current.parent = undefined;
    }

    log.script(`Deleted instance: ${node.path.join("/")}`, "deleted");
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
    return Array.from(this.nodes.values()).filter((node) =>
      this.isScriptNode(node)
    );
  }

  /**
   * Find a node by its path
   */
  private findNodeByPath(path: string[]): TreeNode | undefined {
    return this.pathIndex.get(this.pathKey(path));
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
        this.pathIndex.set(this.pathKey([]), this.root);
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
    let scriptCount = 0;
    let maxDepth = 0;

    for (const node of this.nodes.values()) {
      if (this.isScriptNode(node)) {
        scriptCount += 1;
      }
      const depth = node.path.length;
      if (depth > maxDepth) {
        maxDepth = depth;
      }
    }

    return {
      totalNodes: this.nodes.size,
      scriptNodes: scriptCount,
      maxDepth,
    };
  }
}
