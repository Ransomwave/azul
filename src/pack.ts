import fs from "node:fs";
import path from "node:path";
import { IPCServer } from "./ipc/server.js";
import { FileWriter } from "./fs/fileWriter.js";
import type { TreeNode } from "./fs/treeManager.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import type {
  FullSnapshotMessage,
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
  tags?: string[];
}

interface SourcemapRoot {
  name: string;
  className: string;
  children: SourcemapNode[];
  _azul?: {
    packVersion?: number;
    packedAt?: string;
    mode?: "all" | "scripts-and-descendants";
    placeId?: number;
  };
}

const PACK_VERSION = 1;

/**
 * Packs a one-shot snapshot from Studio into a sourcemap.json.
 */
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

    const { sourcemap, packedCount } = this.buildSourcemap(
      snapshot.data,
      snapshot.placeId,
    );
    this.writeSourcemap(sourcemap, this.outputPath);
    log.success(`Packed ${packedCount} node(s) into ${this.outputPath}`);
  }

  private async requestSnapshot(
    options: SnapshotRequestOptions,
  ): Promise<FullSnapshotMessage | null> {
    return new Promise<FullSnapshotMessage | null>((resolve) => {
      let timeoutHandle: NodeJS.Timeout | null = null;
      let resolved = false;

      const finalize = (result: FullSnapshotMessage | null): void => {
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
        finalize(message);
      });

      this.ipc.onConnection(() => {
        log.info("Studio connected. Waiting for handshake...");
      });

      this.ipc.onHandshake(() => {
        log.info("Handshake complete. Requesting snapshot...");
        this.ipc.requestSnapshot(options);
      });

      timeoutHandle = setTimeout(() => {
        log.error("Timed out waiting for Studio snapshot.");
        finalize(null);
      }, 30000);
    });
  }

  private isScriptClass(className: string): boolean {
    return (
      className === "Script" ||
      className === "LocalScript" ||
      className === "ModuleScript"
    );
  }

  /**
   * Build a fresh sourcemap straight from the Studio snapshot.
   */
  private buildSourcemap(
    snapshot: InstanceData[],
    placeId?: number,
  ): {
    sourcemap: SourcemapRoot;
    packedCount: number;
  } {
    const root: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children: [],
    };

    const fileWriter = new FileWriter(config.syncDir);
    const byGuid = new Map<string, SourcemapNode>();
    byGuid.set("root", root as unknown as SourcemapNode);

    const sorted = [...snapshot].sort((a, b) => {
      if (a.path.length !== b.path.length) {
        return a.path.length - b.path.length;
      }
      return a.path.join("/").localeCompare(b.path.join("/"));
    });

    let packedCount = 0;

    for (const item of sorted) {
      const node: SourcemapNode = {
        name: item.name,
        className: item.className,
        guid: item.guid,
      };

      if (this.isScriptClass(item.className)) {
        const treeNode: TreeNode = {
          guid: item.guid,
          className: item.className,
          name: item.name,
          path: item.path,
          children: new Map(),
        };
        const filePath = fileWriter.getFilePath(treeNode);
        if (fs.existsSync(filePath)) {
          node.filePaths = [
            path.relative(process.cwd(), filePath).replace(/\\/g, "/"),
          ];
          fileWriter.remapScript(item.guid, filePath, item.className);
        }
      }

      if (item.properties && Object.keys(item.properties).length > 0) {
        node.properties = item.properties;
      }
      if (item.attributes && Object.keys(item.attributes).length > 0) {
        node.attributes = item.attributes;
      }
      if (item.tags && item.tags.length > 0) {
        node.tags = item.tags;
      }
      if (node.properties || node.attributes || node.tags) {
        packedCount += 1;
      }

      const parentNode =
        (item.parentGuid && byGuid.get(item.parentGuid)) ||
        (root as unknown as SourcemapNode);
      if (!parentNode.children) parentNode.children = [];
      parentNode.children.push(node);
      byGuid.set(item.guid, node);
    }

    root._azul = {
      packVersion: PACK_VERSION,
      packedAt: new Date().toISOString(),
      mode: this.scriptsAndDescendantsOnly ? "scripts-and-descendants" : "all",
      // 0 means the place was never saved to Roblox, so there is nothing to open.
      placeId: placeId && placeId > 0 ? placeId : undefined,
    };

    return { sourcemap: root, packedCount };
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
}
