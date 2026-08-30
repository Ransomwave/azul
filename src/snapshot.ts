import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { log } from "./util/log.js";
import {
  classifyScriptFileName,
  isScriptFileName,
  replaceSelfRequires,
} from "./util/scriptFile.js";
import type { InstanceData } from "./ipc/messages.js";

export interface SnapshotOptions {
  sourceDir: string;
  destPrefix?: string[];
  skipSymlinks?: boolean;
}

export class SnapshotBuilder {
  private sourceDir: string;
  private destPrefix: string[];
  private skipSymlinks: boolean;

  private folderMap = new Map<string, InstanceData>();
  private results: InstanceData[] = [];
  private scriptPaths = new Set<string>();

  constructor(options: SnapshotOptions) {
    this.sourceDir = path.resolve(options.sourceDir);
    this.destPrefix = options.destPrefix ?? [];
    this.skipSymlinks = options.skipSymlinks !== false; // default: skip links
  }

  public async build(): Promise<InstanceData[]> {
    this.results = [];
    this.folderMap.clear();
    this.scriptPaths.clear();

    await this.walk(this.sourceDir);

    this.results.sort((a, b) => a.path.length - b.path.length);
    return this.results;
  }

  private async walk(dir: string): Promise<void> {
    const entries = await fs.readdir(dir, { withFileTypes: true });

    const files = entries.filter((entry) => entry.isFile());
    const directories = entries.filter((entry) => entry.isDirectory());

    for (const entry of files) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isSymbolicLink && entry.isSymbolicLink()) {
        if (!this.skipSymlinks) {
          continue;
        }
        log.debug(`Skipping symlinked file during snapshot: ${fullPath}`);
        continue;
      }

      if (isScriptFileName(entry.name)) {
        const relSegments = this.relativeSegments(fullPath);
        const { className, scriptName } = classifyScriptFileName(entry.name, {
          stripDisambiguationSuffix: true,
        });
        const dirSegments = relSegments.slice(0, -1);
        if (dirSegments.length > 0) {
          this.ensureFolder(dirSegments);
        }

        const filePathSegments = [
          ...this.destPrefix,
          ...dirSegments,
          scriptName,
        ];
        // Already Azul format on disk, so scriptName is the final instance name
        const source = replaceSelfRequires(
          scriptName,
          await fs.readFile(fullPath, "utf-8"),
        );

        this.scriptPaths.add(this.pathKey(filePathSegments));

        const fileData: InstanceData = {
          guid: this.makeGuid(),
          className,
          name: scriptName,
          path: filePathSegments,
          source,
        };

        this.results.push(fileData);
      }
    }

    for (const entry of directories) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isSymbolicLink && entry.isSymbolicLink()) {
        if (!this.skipSymlinks) {
          continue;
        }
        log.debug(`Skipping symlinked directory during snapshot: ${fullPath}`);
        continue;
      }

      const relSegments = this.relativeSegments(fullPath);
      if (relSegments.length > 0) {
        this.ensureFolder(relSegments);
      }

      await this.walk(fullPath);
    }
  }

  private ensureFolder(segments: string[]): void {
    for (let i = 1; i <= segments.length; i++) {
      const keySegments = segments.slice(0, i);
      const full = [...this.destPrefix, ...keySegments];
      const key = this.pathKey(full);
      if (this.scriptPaths.has(key)) continue;
      if (this.folderMap.has(key)) continue;
      const data: InstanceData = {
        guid: this.makeGuid(),
        className: "Folder",
        name: keySegments[i - 1],
        path: full,
      };
      this.folderMap.set(key, data);
      this.results.push(data);
    }
  }

  private relativeSegments(targetPath: string): string[] {
    const rel = path.relative(this.sourceDir, targetPath);
    if (!rel || rel === "") return [];
    return rel.split(path.sep).filter(Boolean);
  }

  private makeGuid(): string {
    return randomUUID().replace(/-/g, "");
  }

  private pathKey(segments: string[]): string {
    return segments.join("/");
  }
}
