import fs from "node:fs";
import path from "node:path";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import type { InstanceData, StudioMessage } from "./ipc/messages.js";

interface PackOptions {
  outputPath?: string;
  scriptsAndDescendantsOnly?: boolean;
}

interface SourcemapNode {
  name: string;
  className: string;
  guid?: string;
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
    if (!fs.existsSync(this.outputPath)) {
      log.error(
        `Sourcemap not found at ${this.outputPath}. Run 'azul' once first.`,
      );
      return;
    }

    log.info(`Waiting for Studio to connect on port ${config.port}...`);
    const snapshot = await this.requestPackedSnapshot();
    if (!snapshot) {
      log.error("Failed to receive snapshot from Studio for packing.");
      return;
    }

    const packedCount = this.packIntoSourcemap(snapshot, this.outputPath);
    log.success(`Packed ${packedCount} node(s) into ${this.outputPath}`);
  }

  private async requestPackedSnapshot(): Promise<InstanceData[] | null> {
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
        log.info("Studio connected. Requesting pack snapshot...");
        this.ipc.requestSnapshot({
          includeProperties: true,
          scriptsAndDescendantsOnly: this.scriptsAndDescendantsOnly,
        });
      });

      timeoutHandle = setTimeout(() => {
        log.error("Timed out waiting for Studio snapshot.");
        finalize(null);
      }, 30000);
    });
  }

  private packIntoSourcemap(
    snapshot: InstanceData[],
    sourcemapPath: string,
  ): number {
    const raw = fs.readFileSync(sourcemapPath, "utf8");
    const sourcemap = JSON.parse(raw) as SourcemapRoot;

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

    fs.writeFileSync(
      sourcemapPath,
      `${JSON.stringify(sourcemap, null, 2)}\n`,
      "utf8",
    );

    return packed;
  }

  private pathClassKey(pathSegments: string[], className: string): string {
    return `${pathSegments.join("\u0001")}::${className}`;
  }
}
