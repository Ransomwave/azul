import path from "node:path";
import fs from "node:fs";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import { SnapshotBuilder } from "./snapshot.js";
import { RojoSnapshotBuilder } from "./snapshot/rojo/index.js";
import type { InstanceData } from "./ipc/messages.js";
import { replaceSelfRequires } from "./util/scriptFile.js";
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
  destructive?: boolean;
}

export class BuildCommand {
  private ipc: IPCServer;
  private syncDir: string;
  private rojoMode: boolean;
  private rojoProjectFile?: string;
  private applySourcemapProperties: boolean;
  private useSourcemapAsSource: boolean;
  private sourcemapPath: string;
  private destructive: boolean;

  constructor(options: BuildOptions = {}) {
    this.syncDir = path.resolve(options.syncDir ?? config.syncDir);
    this.rojoMode = Boolean(options.rojoMode);
    this.rojoProjectFile = options.rojoProjectFile;
    this.applySourcemapProperties = options.applySourcemapProperties !== false;
    this.useSourcemapAsSource = options.useSourcemapAsSource === true;
    this.sourcemapPath = path.resolve(
      options.sourcemapPath ?? config.sourcemapPath,
    );
    this.destructive = options.destructive === true;
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
    let builtFromSourcemap = false; // Was the build done from the sourcemap (true) or from the filesystem (false)?

    if (!this.rojoMode && this.useSourcemapAsSource) {
      const built = buildInstancesFromSourcemap(this.sourcemapPath);
      // An empty array parses fine but contributes nothing, so treat it as a miss
      if (!built || built.length === 0) {
        log.warn(
          "Falling back to filesystem build because the sourcemap was empty, missing, or could not be parsed.",
        );
      } else {
        // Rewrite `@self` requires in the built instances to resolve against the instance name
        for (const instance of built) {
          if (instance.source) {
            instance.source = replaceSelfRequires(
              instance.name,
              instance.source,
            );
          }
        }
        instances = built;
      }
    }

    builtFromSourcemap = instances.length > 0;

    if (instances.length === 0) {
      try {
        instances = await builder.build();
      } catch (error) {
        log.error(`${error}`);
        return;
      }
    }

    // Apply properties from the sourcemap if requested, but only if the build was not done from the sourcemap (to avoid double-applying properties)
    if (
      !this.rojoMode &&
      this.applySourcemapProperties &&
      !builtFromSourcemap
    ) {
      const index = loadSourcemapPropertyIndex(this.sourcemapPath);
      const applied = applySourcemapProperties(instances, index);
      if (applied <= 0) {
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
        log.info("Studio connected. Waiting for handshake...");
      });

      this.ipc.onHandshake(() => {
        log.info("Handshake complete. Sending build snapshot...");
        this.ipc.send({
          type: "buildSnapshot",
          data: instances,
          destructive: this.destructive,
        });
        log.success(`Sent ${instances.length} instances`);
        setTimeout(() => {
          this.ipc.close();
          resolve();
        }, 200);
      });
    });
  }
}
