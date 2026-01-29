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
  parentGuid?: string | null;
  source?: string;
  children: Map<string, TreeNode>;
  parent?: TreeNode;
}

/**
 * Manages the in-memory representation of Studio's DataModel
 */
export class TreeManager {
  private nodes: Map<string, TreeNode> = new Map();
  private pathIndex: Map<string, Set<TreeNode>> = new Map(); // pathKey → TreeNodes (same name siblings supported)
  private root: TreeNode | null = null;

  private pathKey(path: string[]): string {
    return path.join("\u0000");
  }

  private addToPathIndex(node: TreeNode): void {
    const key = this.pathKey(node.path);
    const bucket = this.pathIndex.get(key) ?? new Set<TreeNode>();
    bucket.add(node);
    this.pathIndex.set(key, bucket);
  }

  private removeFromPathIndex(node: TreeNode): void {
    const key = this.pathKey(node.path);
    const bucket = this.pathIndex.get(key);
    if (!bucket) return;

    bucket.delete(node);
    if (bucket.size === 0) {
      this.pathIndex.delete(key);
    }
  }

  private registerSubtree(node: TreeNode): void {
    const stack: TreeNode[] = [node];

    while (stack.length > 0) {
      const current = stack.pop()!;
      this.addToPathIndex(current);

      for (const child of current.children.values()) {
        stack.push(child);
      }
    }
  }

  private unregisterSubtree(node: TreeNode): void {
    const stack: TreeNode[] = [node];

    while (stack.length > 0) {
      const current = stack.pop()!;
      this.removeFromPathIndex(current);

      for (const child of current.children.values()) {
        stack.push(child);
      }
    }
  }

  public updateInstance(instance: InstanceData): {
    node: TreeNode;
    pathChanged: boolean;
    nameChanged: boolean;
    parentChanged: boolean;
    isNew: boolean;
    prevPath?: string[];
    prevName?: string;
  } | null {
    const existing = this.nodes.get(instance.guid);
    const hasParentHint = instance.parentGuid !== undefined;
    const incomingParentGuid = hasParentHint
      ? (instance.parentGuid ?? null)
      : null;

    if (existing) {
      const prevPath = [...existing.path];
      const prevName = existing.name;
      const pathChanged = !this.pathsEqual(existing.path, instance.path);
      const nameChanged = existing.name !== instance.name;
      const currentParentGuid =
        existing.parent?.guid ?? existing.parentGuid ?? null;
      const nextParentGuid = hasParentHint
        ? incomingParentGuid
        : currentParentGuid;
      const parentChanged =
        hasParentHint && nextParentGuid !== currentParentGuid;

      const nextSource =
        instance.source !== undefined ? instance.source : existing.source;

      if (pathChanged) {
        this.unregisterSubtree(existing);
      }

      existing.className = instance.className;
      existing.name = instance.name;
      existing.path = instance.path;
      existing.parentGuid = nextParentGuid;
      existing.source = nextSource;

      if (pathChanged || nameChanged || parentChanged) {
        this.reparentNode(existing, instance.path, nextParentGuid);
        this.recalculateChildPaths(existing);
        this.registerSubtree(existing);
      }

      log.script(`Updated instance: ${instance.path.join("/")}`, "updated");
      return {
        node: existing,
        pathChanged,
        nameChanged,
        parentChanged,
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
      parentGuid: incomingParentGuid,
      source: instance.source,
      children: new Map(),
    };

    this.nodes.set(instance.guid, node);
    this.reparentNode(node, instance.path, incomingParentGuid);
    this.recalculateChildPaths(node);
    this.registerSubtree(node);

    log.script(`Created instance: ${instance.path.join("/")}`, "created");
    return {
      node,
      pathChanged: false,
      nameChanged: false,
      parentChanged: false,
      isNew: true,
    };
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
        parentGuid: instance.parentGuid ?? null,
        source: instance.source,
        children: new Map(),
      };
      this.nodes.set(instance.guid, node);
      this.addToPathIndex(node);
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
            parentGuid: null,
            children: new Map(),
          };
          this.nodes.set("root", this.root);
          this.addToPathIndex(this.root);
        }
        this.root.children.set(node.guid, node);
        node.parent = this.root;
        node.parentGuid = this.root.guid;
        log.debug(`Assigned root parent for: ${instance.path.join("/")}`);
      } else {
        // Find parent by matching path
        const parentPath = instance.path.slice(0, -1);
        const explicitParentGuid = instance.parentGuid ?? null;
        let parent: TreeNode | undefined;

        if (explicitParentGuid) {
          parent = this.nodes.get(explicitParentGuid);
        }

        if (!parent) {
          parent = this.findNodeByPath(parentPath);
        }

        if (parent) {
          parent.children.set(node.guid, node);
          node.parent = parent;
          node.parentGuid = parent.guid;
          log.debug(`Assigned parent for: ${instance.path.join("/")}`);
        } else {
          log.warn(`Parent not found for ${instance.path.join("/")}`);
        }
      }
    }

    log.success(`Tree built: ${this.nodes.size} nodes`);
  }

  /**
   * Update child paths iteratively
   */
  private recalculateChildPaths(node: TreeNode): void {
    const queue: TreeNode[] = [...node.children.values()];

    while (queue.length > 0) {
      const child = queue.shift()!;
      child.path = [...child.parent!.path, child.name];

      for (const grandchild of child.children.values()) {
        queue.push(grandchild);
      }
    }
  }

  public getDescendantScripts(guid: string): TreeNode[] {
    const start = this.nodes.get(guid);
    if (!start) {
      return [];
    }

    const scripts: TreeNode[] = [];
    const stack: TreeNode[] = [...start.children.values()];

    while (stack.length > 0) {
      const node = stack.pop()!;

      if (this.isScriptNode(node)) {
        scripts.push(node);
      }

      for (const child of node.children.values()) {
        stack.push(child);
      }
    }

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

      this.removeFromPathIndex(current);
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
      this.isScriptNode(node),
    );
  }

  /**
   * Find a node by its path
   */
  private findNodeByPath(path: string[]): TreeNode | undefined {
    const bucket = this.pathIndex.get(this.pathKey(path));
    if (!bucket || bucket.size === 0) {
      return undefined;
    }

    if (bucket.size === 1) {
      return bucket.values().next().value;
    }

    // Ambiguous path (same-name siblings); caller should use parent GUIDs instead
    log.debug(
      `Multiple nodes share path ${path.join("/")}, skipping path lookup`,
    );
    return undefined;
  }

  /**
   * Re-parent a node based on its path
   */
  private reparentNode(
    node: TreeNode,
    path: string[],
    parentGuid?: string | null,
  ): void {
    // Remove from old parent
    if (node.parent) {
      node.parent.children.delete(node.guid);
    }

    // Find new parent (prefer explicit parent GUID when present)
    let parent: TreeNode | undefined;

    if (parentGuid) {
      parent = this.nodes.get(parentGuid);
    }

    if (!parent) {
      if (path.length === 1) {
        // Root service
        if (!this.root) {
          this.root = {
            guid: "root",
            className: "DataModel",
            name: "game",
            path: [],
            parentGuid: null,
            children: new Map(),
          };
          this.nodes.set("root", this.root);
          this.addToPathIndex(this.root);
        }
        parent = this.root;
      } else {
        const parentPath = path.slice(0, -1);
        parent = this.findNodeByPath(parentPath);
      }
    }

    if (parent) {
      parent.children.set(node.guid, node);
      node.parent = parent;
      node.parentGuid = parent.guid;
    } else {
      log.warn(`Parent not found for re-parenting: ${path.join("/")}`);
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
