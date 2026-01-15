import path from "node:path";
import { IPCServer } from "./ipc/server.js";
import { config } from "./config.js";
import { log } from "./util/log.js";
import { SnapshotBuilder } from "./snapshot.js";
import { RojoSnapshotBuilder } from "./snapshot/rojo.js";

interface BuildOptions {
  syncDir?: string;
  rojoMode?: boolean;
  rojoProjectFile?: string;
}

export class BuildCommand {
  private ipc: IPCServer;
  private syncDir: string;
  private rojoMode: boolean;
  private rojoProjectFile?: string;

  constructor(options: BuildOptions = {}) {
    this.syncDir = path.resolve(options.syncDir ?? config.syncDir);
    this.rojoMode = Boolean(options.rojoMode);
    this.rojoProjectFile = options.rojoProjectFile;
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
        }`
      );
    } else {
      log.info(`Preparing build snapshot from ${this.syncDir}`);
    }
    let instances: InstanceData[] = [];
    try {
      instances = await builder.build();
    } catch (error) {
      log.error(`${error}`);
      return;
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
