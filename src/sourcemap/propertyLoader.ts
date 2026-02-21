import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { log } from "../util/log.js";
import type { InstanceData } from "../ipc/messages.js";

interface SourcemapNode {
  name: string;
  className: string;
  guid?: string;
  properties?: Record<string, unknown>;
  attributes?: Record<string, unknown>;
  children?: SourcemapNode[];
  filePaths?: string[];
}

interface SourcemapRoot {
  name: string;
  className: string;
  children: SourcemapNode[];
}

export interface SourcemapPropertyIndex {
  byGuid: Map<string, SourcemapNode>;
  byPathClass: Map<string, SourcemapNode[]>;
}

const pathClassKey = (segments: string[], className: string): string =>
  `${segments.join("\u0001")}::${className}`;

export function loadSourcemapPropertyIndex(
  sourcemapPath: string,
): SourcemapPropertyIndex | null {
  const resolved = path.resolve(sourcemapPath);
  if (!fs.existsSync(resolved)) {
    log.debug(`No sourcemap found at ${resolved}; skipping property merge.`);
    return null;
  }

  let root: SourcemapRoot;
  try {
    const raw = fs.readFileSync(resolved, "utf8");
    root = JSON.parse(raw) as SourcemapRoot;
  } catch (error) {
    log.warn(`Failed to read sourcemap at ${resolved}: ${error}`);
    return null;
  }

  const byGuid = new Map<string, SourcemapNode>();
  const byPathClass = new Map<string, SourcemapNode[]>();

  const visit = (node: SourcemapNode, currentPath: string[]) => {
    const nodePath = [...currentPath, node.name];

    if (node.guid) {
      byGuid.set(node.guid, node);
    }

    const key = pathClassKey(nodePath, node.className);
    const bucket = byPathClass.get(key) ?? [];
    bucket.push(node);
    byPathClass.set(key, bucket);

    for (const child of node.children ?? []) {
      visit(child, nodePath);
    }
  };

  for (const child of root.children ?? []) {
    visit(child, []);
  }

  return { byGuid, byPathClass };
}

export function applySourcemapProperties(
  instances: InstanceData[],
  index: SourcemapPropertyIndex | null,
): number {
  if (!index) return 0;

  let applied = 0;
  for (const instance of instances) {
    const match = findNodeForInstance(instance, index);
    if (!match) continue;

    const hasProps =
      match.properties && Object.keys(match.properties).length > 0;
    const hasAttrs =
      match.attributes && Object.keys(match.attributes).length > 0;

    if (!hasProps && !hasAttrs) continue;

    if (hasProps) {
      instance.properties = match.properties;
    }

    if (hasAttrs) {
      instance.attributes = match.attributes;
    }

    applied += 1;
  }

  return applied;
}

export function buildInstancesFromSourcemap(
  sourcemapPath: string,
): InstanceData[] | null {
  const resolved = path.resolve(sourcemapPath);
  if (!fs.existsSync(resolved)) {
    log.warn(`Sourcemap not found at ${resolved}`);
    return null;
  }

  let root: SourcemapRoot;
  try {
    const raw = fs.readFileSync(resolved, "utf8");
    root = JSON.parse(raw) as SourcemapRoot;
  } catch (error) {
    log.error(`Failed to parse sourcemap at ${resolved}: ${error}`);
    return null;
  }

  const results: InstanceData[] = [];

  const visit = (
    node: SourcemapNode,
    currentPath: string[],
    parentGuid?: string,
  ) => {
    const nodePath = [...currentPath, node.name];
    const guid = node.guid ?? randomUUID().replace(/-/g, "");

    const instance: InstanceData = {
      guid,
      className: node.className,
      name: node.name,
      path: nodePath,
      parentGuid,
    };

    if (node.properties) instance.properties = node.properties;
    if (node.attributes) instance.attributes = node.attributes;

    const isScript =
      node.className === "Script" ||
      node.className === "LocalScript" ||
      node.className === "ModuleScript";

    if (isScript && node.filePaths && node.filePaths.length > 0) {
      const scriptPath = path.resolve(process.cwd(), node.filePaths[0]);
      try {
        instance.source = fs.readFileSync(scriptPath, "utf8");
      } catch (error) {
        log.warn(
          `Failed to read script file for ${nodePath.join("/")}: ${error}`,
        );
      }
    }

    results.push(instance);

    for (const child of node.children ?? []) {
      visit(child, nodePath, guid);
    }
  };

  for (const child of root.children ?? []) {
    visit(child, []);
  }

  results.sort((a, b) => a.path.length - b.path.length);
  return results;
}

function findNodeForInstance(
  instance: InstanceData,
  index: SourcemapPropertyIndex,
): SourcemapNode | null {
  if (instance.guid) {
    const byGuid = index.byGuid.get(instance.guid);
    if (byGuid) return byGuid;
  }

  const key = pathClassKey(instance.path, instance.className);
  const bucket = index.byPathClass.get(key);
  if (!bucket || bucket.length === 0) return null;

  if (bucket.length === 1) return bucket[0];

  // Prefer a node that also carries a guid to reduce ambiguity
  return bucket.find((node) => Boolean(node.guid)) ?? bucket[0];
}
