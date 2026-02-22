import fs from "node:fs";
import path from "node:path";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import type {
  InstanceData,
  SnapshotRequestOptions,
  StudioMessage,
} from "./ipc/messages.js";

interface PackOptions {
  outputPath?: string;
  scriptsAndDescendantsOnly?: boolean;
}

interface SourcemapNode {
  name: string;
  className: string;
  guid?: string;
  filePaths?: string[];
  children?: SourcemapNode[];
  properties?: Record<string, unknown>;
  attributes?: Record<string, unknown>;
}

interface SourcemapRoot {
  name: string;
  className: string;
  children: SourcemapNode[];
  _azul?: {
    packVersion?: number;
    packedAt?: string;
    mode?: "all" | "scripts-and-descendants";
  };
}

export class PackCommand {
  private ipc: IPCServer;
  private outputPath: string;
  private scriptsAndDescendantsOnly: boolean;

  constructor(options: PackOptions = {}) {
    this.outputPath = path.resolve(options.outputPath ?? config.sourcemapPath);
    this.scriptsAndDescendantsOnly = Boolean(options.scriptsAndDescendantsOnly);
    this.ipc = new IPCServer(config.port, undefined, {
      requestSnapshotOnConnect: false,
    });
  }

  public async run(): Promise<void> {
    log.info(`Waiting for Studio to connect on port ${config.port}...`);
    const snapshot = await this.requestSnapshot({
      includeProperties: true,
      scriptsAndDescendantsOnly: this.scriptsAndDescendantsOnly,
    });

    if (!snapshot) {
      log.error("Failed to receive snapshot from Studio for packing.");
      return;
    }

    const existing = this.readExistingSourcemap();
    const regenerated = this.regenerateSourcemap(snapshot, existing);
    const packedCount = this.packIntoSourcemap(snapshot, regenerated);

    this.writeSourcemap(regenerated, this.outputPath);
    log.success(`Packed ${packedCount} node(s) into ${this.outputPath}`);
  }

  private async requestSnapshot(
    options: SnapshotRequestOptions,
  ): Promise<InstanceData[] | null> {
    return new Promise<InstanceData[] | null>((resolve) => {
      let timeoutHandle: NodeJS.Timeout | null = null;
      let resolved = false;

      const finalize = (result: InstanceData[] | null): void => {
        if (resolved) return;
        resolved = true;

        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
          timeoutHandle = null;
        }

        setTimeout(() => {
          this.ipc.close();
        }, 200);

        resolve(result);
      };

      this.ipc.onMessage((message: StudioMessage) => {
        if (message.type !== "fullSnapshot") return;
        finalize(message.data);
      });

      this.ipc.onConnection(() => {
        log.info("Studio connected. Requesting snapshot...");
        this.ipc.requestSnapshot(options);
      });

      timeoutHandle = setTimeout(() => {
        log.error("Timed out waiting for Studio snapshot.");
        finalize(null);
      }, 30000);
    });
  }

  private readExistingSourcemap(): SourcemapRoot | null {
    if (!fs.existsSync(this.outputPath)) {
      return null;
    }

    try {
      const raw = fs.readFileSync(this.outputPath, "utf8");
      return JSON.parse(raw) as SourcemapRoot;
    } catch (error) {
      log.warn(
        `Failed to read existing sourcemap at ${this.outputPath}: ${error}`,
      );
      return null;
    }
  }

  private regenerateSourcemap(
    snapshot: InstanceData[],
    existing: SourcemapRoot | null,
  ): SourcemapRoot {
    const root: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children: [],
    };

    const guidFilePaths = new Map<string, string[]>();
    const pathClassFilePaths = new Map<string, string[][]>();
    const pathClassCursor = new Map<string, number>();

    const indexExisting = (
      node: SourcemapNode,
      currentPath: string[],
    ): void => {
      const nodePath = [...currentPath, node.name];
      if (node.filePaths && node.filePaths.length > 0) {
        if (node.guid) {
          guidFilePaths.set(node.guid, node.filePaths);
        }

        const key = this.pathClassKey(nodePath, node.className);
        const bucket = pathClassFilePaths.get(key) ?? [];
        bucket.push(node.filePaths);
        pathClassFilePaths.set(key, bucket);
      }

      for (const child of node.children ?? []) {
        indexExisting(child, nodePath);
      }
    };

    for (const child of existing?.children ?? []) {
      indexExisting(child, []);
    }

    const byGuid = new Map<string, SourcemapNode>();
    byGuid.set("root", root as unknown as SourcemapNode);

    const sorted = [...snapshot].sort((a, b) => {
      if (a.path.length !== b.path.length) {
        return a.path.length - b.path.length;
      }
      return a.path.join("/").localeCompare(b.path.join("/"));
    });

    for (const item of sorted) {
      const node: SourcemapNode = {
        name: item.name,
        className: item.className,
        guid: item.guid,
      };

      const directFilePaths = guidFilePaths.get(item.guid);
      if (directFilePaths && directFilePaths.length > 0) {
        node.filePaths = directFilePaths;
      } else {
        const key = this.pathClassKey(item.path, item.className);
        const bucket = pathClassFilePaths.get(key);
        if (bucket && bucket.length > 0) {
          const cursor = pathClassCursor.get(key) ?? 0;
          const candidate = bucket[cursor];
          if (candidate && candidate.length > 0) {
            node.filePaths = candidate;
            pathClassCursor.set(key, cursor + 1);
          }
        }
      }

      let parentNode = root as SourcemapNode;
      if (item.parentGuid && item.parentGuid !== "root") {
        parentNode = byGuid.get(item.parentGuid) ?? root;
      }

      if (!parentNode.children) {
        parentNode.children = [];
      }
      parentNode.children.push(node);
      byGuid.set(item.guid, node);
    }

    return root;
  }

  private packIntoSourcemap(
    snapshot: InstanceData[],
    sourcemap: SourcemapRoot,
  ): number {
    const byGuid = new Map<string, InstanceData>();
    const byPathClass = new Map<string, InstanceData[]>();
    for (const item of snapshot) {
      byGuid.set(item.guid, item);
      const key = this.pathClassKey(item.path, item.className);
      const bucket = byPathClass.get(key) ?? [];
      bucket.push(item);
      byPathClass.set(key, bucket);
    }

    const usedGuids = new Set<string>();
    let packed = 0;

    const visit = (node: SourcemapNode, currentPath: string[]): void => {
      const nodePath = [...currentPath, node.name];
      let match: InstanceData | undefined;

      if (node.guid) {
        const direct = byGuid.get(node.guid);
        if (direct) {
          match = direct;
          usedGuids.add(direct.guid);
        }
      }

      if (!match) {
        const key = this.pathClassKey(nodePath, node.className);
        const bucket = byPathClass.get(key);
        if (bucket && bucket.length > 0) {
          match = bucket.find((candidate) => !usedGuids.has(candidate.guid));
          if (match) {
            usedGuids.add(match.guid);
          }
        }
      }

      if (match) {
        if (match.properties && Object.keys(match.properties).length > 0) {
          node.properties = match.properties;
        } else if (!this.scriptsAndDescendantsOnly) {
          delete node.properties;
        }

        if (match.attributes && Object.keys(match.attributes).length > 0) {
          node.attributes = match.attributes;
        } else if (!this.scriptsAndDescendantsOnly) {
          delete node.attributes;
        }

        if (match.properties || match.attributes) {
          packed += 1;
        }
      } else if (!this.scriptsAndDescendantsOnly) {
        delete node.properties;
        delete node.attributes;
      }

      for (const child of node.children ?? []) {
        visit(child, nodePath);
      }
    };

    for (const child of sourcemap.children ?? []) {
      visit(child, []);
    }

    sourcemap._azul = {
      packVersion: 1,
      packedAt: new Date().toISOString(),
      mode: this.scriptsAndDescendantsOnly ? "scripts-and-descendants" : "all",
    };

    return packed;
  }

  private writeSourcemap(sourcemap: SourcemapRoot, outputPath: string): void {
    const dir = path.dirname(outputPath);
    if (dir && dir !== "." && !fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    fs.writeFileSync(
      outputPath,
      `${JSON.stringify(sourcemap, null, 2)}\n`,
      "utf8",
    );
  }

  private pathClassKey(pathSegments: string[], className: string): string {
    return `${pathSegments.join("\u0001")}::${className}`;
  }
}
