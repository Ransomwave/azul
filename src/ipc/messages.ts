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
  parentGuid?: string | null; // parent instance GUID
  source?: string; // Only present for Script/LocalScript/ModuleScript
}

/**
 * Messages from Studio → Daemon
 */
export type StudioPayloadMessage =
  | FullSnapshotMessage
  | InstanceUpdatedMessage
  | ScriptChangedMessage
  | DeletedMessage
  | PingMessage
  | ClientDisconnect
  | PushConfigMessage;

export interface BatchMessage {
  type: "batch";
  messages: StudioPayloadMessage[];
}

export type StudioMessage = StudioPayloadMessage | BatchMessage;

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

export interface ClientDisconnect {
  type: "clientDisconnect";
}

export interface PushConfigMessage {
  type: "pushConfig";
  config: PushConfig;
}

/**
 * Messages from Daemon → Studio
 */
export type DaemonMessage =
  | PatchScriptMessage
  | RequestSnapshotMessage
  | PongMessage
  | ErrorMessage
  | BuildSnapshotMessage
  | RequestPushConfigMessage
  | PushSnapshotMessage;

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

export interface BuildSnapshotMessage {
  type: "buildSnapshot";
  data: InstanceData[];
}

export interface RequestPushConfigMessage {
  type: "requestPushConfig";
}

export interface PushSnapshotMessage {
  type: "pushSnapshot";
  mappings: PushSnapshotMapping[];
}

export interface PushSnapshotMapping {
  destination: string[];
  destructive?: boolean;
  instances: InstanceData[];
}

export interface PushConfig {
  mappings: PushConfigMapping[];
  port?: number;
  debugMode?: boolean;
  deleteOrphansOnConnect?: boolean;
}

export interface PushConfigMapping {
  source: string;
  destination: string[];
  destructive?: boolean;
  rojoMode?: boolean;
}
