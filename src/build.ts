import path from "node:path";
import fs from "node:fs";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import { SnapshotBuilder } from "./snapshot.js";
import { RojoSnapshotBuilder } from "./snapshot/rojo.js";
import type { InstanceData } from "./ipc/messages.js";
import {
  applySourcemapProperties,
  buildInstancesFromSourcemap,
  loadSourcemapPropertyIndex,
} from "./sourcemap/propertyLoader.js";

interface BuildOptions {
  syncDir?: string;
  rojoMode?: boolean;
  rojoProjectFile?: string;
  applySourcemapProperties?: boolean;
  useSourcemapAsSource?: boolean;
  sourcemapPath?: string;
}

export class BuildCommand {
  private ipc: IPCServer;
  private syncDir: string;
  private rojoMode: boolean;
  private rojoProjectFile?: string;
  private applySourcemapProperties: boolean;
  private useSourcemapAsSource: boolean;
  private sourcemapPath: string;

  constructor(options: BuildOptions = {}) {
    this.syncDir = path.resolve(options.syncDir ?? config.syncDir);
    this.rojoMode = Boolean(options.rojoMode);
    this.rojoProjectFile = options.rojoProjectFile;
    this.applySourcemapProperties = options.applySourcemapProperties !== false;
    this.useSourcemapAsSource = options.useSourcemapAsSource === true;
    this.sourcemapPath = path.resolve(
      options.sourcemapPath ?? config.sourcemapPath,
    );
    this.ipc = new IPCServer(config.port, undefined, {
      requestSnapshotOnConnect: false,
    });
  }

  public async run(): Promise<void> {
    const builder = this.rojoMode
      ? new RojoSnapshotBuilder({
          projectFile: this.rojoProjectFile,
          cwd: process.cwd(),
          destPrefix: [],
        })
      : new SnapshotBuilder({
          sourceDir: this.syncDir,
          destPrefix: [],
          skipSymlinks: true,
        });

    if (this.rojoMode) {
      log.info(
        `Preparing Rojo compatibility build from ${
          this.rojoProjectFile ?? "default.project.json"
        }`,
      );
    } else {
      log.info(`Preparing build snapshot from ${this.syncDir}`);
    }
    let instances: InstanceData[] = [];

    if (!this.rojoMode && this.useSourcemapAsSource) {
      const built = buildInstancesFromSourcemap(this.sourcemapPath);
      if (!built) {
        log.warn(
          "Falling back to filesystem build because sourcemap import failed.",
        );
      } else {
        instances = built;
      }
    }

    if (instances.length === 0) {
      try {
        instances = await builder.build();
      } catch (error) {
        log.error(`${error}`);
        return;
      }
    }

    if (
      !this.rojoMode &&
      this.applySourcemapProperties &&
      !this.useSourcemapAsSource
    ) {
      const index = loadSourcemapPropertyIndex(this.sourcemapPath);
      const applied = applySourcemapProperties(instances, index);
      if (applied > 0) {
        log.success(
          `Applied properties/attributes from sourcemap to ${applied} instance(s)`,
        );
      } else {
        if (!index && fs.existsSync(this.sourcemapPath)) {
          log.warn(
            "Sourcemap present but could not be parsed; continuing without properties.",
          );
        } else {
          log.info(
            "No packed properties found in sourcemap; continuing with script/folder snapshot only.",
          );
        }
      }
    }

    log.info(`Waiting for Studio to connect on port ${config.port}...`);

    await new Promise<void>((resolve) => {
      this.ipc.onConnection(() => {
        log.info("Studio connected. Sending build snapshot...");
        this.ipc.send({ type: "buildSnapshot", data: instances });
        log.success(`Sent ${instances.length} instances`);
        setTimeout(() => {
          this.ipc.close();
          resolve();
        }, 200);
      });
    });
  }
}
