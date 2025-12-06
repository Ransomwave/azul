/**
 * Types for communication protocol between Studio and Daemon
 */

export type InstanceClassName =
  | "Script"
  | "LocalScript"
  | "ModuleScript"
  | "Folder"
  | "Model"
  | "Part"
  | "MeshPart"
  | "Tool"
  | "Configuration"
  | string; // Allow any Roblox class

/**
 * Represents a single instance in the DataModel
 */
export interface InstanceData {
  guid: string;
  className: InstanceClassName;
  name: string;
  path: string[]; // ["ReplicatedStorage", "Modules", "Foo"]
  source?: string; // Only present for Script/LocalScript/ModuleScript
}

/**
 * Messages from Studio → Daemon
 */
export type StudioMessage =
  | FullSnapshotMessage
  | InstanceUpdatedMessage
  | ScriptChangedMessage
  | DeletedMessage
  | PingMessage;

export interface FullSnapshotMessage {
  type: "fullSnapshot";
  data: InstanceData[];
}

export interface InstanceUpdatedMessage {
  type: "instanceUpdated";
  data: InstanceData;
}

export interface ScriptChangedMessage {
  type: "scriptChanged";
  guid: string;
  path: string[];
  className: InstanceClassName;
  source: string;
}

export interface DeletedMessage {
  type: "deleted";
  guid: string;
}

export interface PingMessage {
  type: "ping";
}

/**
 * Messages from Daemon → Studio
 */
export type DaemonMessage =
  | PatchScriptMessage
  | RequestSnapshotMessage
  | PongMessage
  | ErrorMessage;

export interface PatchScriptMessage {
  type: "patchScript";
  guid: string;
  source: string;
}

export interface RequestSnapshotMessage {
  type: "requestSnapshot";
}

export interface PongMessage {
  type: "pong";
}

export interface ErrorMessage {
  type: "error";
  message: string;
}
