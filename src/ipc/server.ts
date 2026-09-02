import { WebSocketServer, WebSocket } from "ws";
import { log } from "../util/log.js";
import type { StudioMessage, DaemonMessage } from "./messages.js";
import type { SnapshotRequestOptions } from "./messages.js";
import type { Server as HttpServer } from "http";
import {
  getCurrentVersion,
  isVersionCompatible,
} from "../util/versionUtils.js";

const DAEMON_VERSION = getCurrentVersion();

export type MessageHandler = (message: StudioMessage) => void;

interface IPCServerOptions {
  requestSnapshotOnConnect?: boolean;
}

export class IPCServer {
  private wss: WebSocketServer;
  private client: WebSocket | null = null;
  private messageHandler: MessageHandler | null = null;
  private connectionHandler: (() => void) | null = null;
  private handshakeHandler: (() => void) | null = null;
  private requestSnapshotOnConnect: boolean;
  private pingIntervals = new Map<WebSocket, NodeJS.Timeout>();
  private handshakeComplete = false;

  constructor(port?: number, server?: HttpServer, options?: IPCServerOptions) {
    this.requestSnapshotOnConnect = options?.requestSnapshotOnConnect !== false;
    if (server) {
      // Use existing HTTP server
      this.wss = new WebSocketServer({
        server,
        // perMessageDeflate: false, // Roblox WebSocket client does not negotiate RSV2/RSV3 extensions
        maxPayload: 256 * 1024 * 1024, // 256 MB
      });
    } else {
      // Create standalone WebSocket server
      this.wss = new WebSocketServer({
        port: port || 8080,
        // perMessageDeflate: false, // avoid RSV2/RSV3 bits from compression
        maxPayload: 256 * 1024 * 1024, // 256 MB
      });
    }
    this.setupServer();
  }

  private setupServer(): void {
    this.wss.on("connection", (ws) => {
      log.info("Studio client connected");
      log.info("Waiting for Studio messages...");

      // Disconnect previous client if exists
      if (this.client) {
        log.warn("Disconnecting previous client");
        this.client.close();
      }

      this.client = ws;
      this.handshakeComplete = false;

      if (this.connectionHandler) {
        this.connectionHandler();
      }

      ws.on("message", (data) => {
        try {
          const message: StudioMessage = JSON.parse(data.toString());
          log.debug(`Received: ${message.type}`);

          if (message.type === "handshakeStudio") {
            void this.handleHandshake(message.version);
            return;
          }

          if (this.messageHandler) {
            this.messageHandler(message);
          }
        } catch (error) {
          log.error("Failed to parse message:", error);
          this.sendError("Invalid JSON message");
        }
      });

      ws.on("close", () => {
        const pingInterval = this.pingIntervals.get(ws);
        if (pingInterval) {
          clearInterval(pingInterval);
          this.pingIntervals.delete(ws);
        }

        log.info("Studio client disconnected");
        this.client = null;
        this.handshakeComplete = false;
      });

      ws.on("error", (error) => {
        log.error("WebSocket error:", error);
      });

      // Set up ping/pong to keep connection alive
      ws.on("pong", () => {
        log.debug("Received pong from client");
      });

      // Send ping every 30 seconds
      const pingInterval = setInterval(() => {
        if (this.client === ws && ws.readyState === WebSocket.OPEN) {
          ws.ping();
        } else {
          clearInterval(pingInterval);
          this.pingIntervals.delete(ws);
        }
      }, 30000);
      this.pingIntervals.set(ws, pingInterval);

      // Request initial snapshot after a brief delay
      if (this.requestSnapshotOnConnect) {
        setTimeout(() => {
          if (this.client === ws) {
            this.send({ type: "requestSnapshot" });
          }
        }, 100);
      }
    });

    this.wss.on("listening", () => {
      log.success("WebSocket server ready");
    });

    this.wss.on("error", (error) => {
      log.error("WebSocket server error:", error);
    });
  }

  /**
   * Handles the handshake process with the Studio client, verifying version compatibility and sending a handshake acknowledgment.
   * If the versions are incompatible, it throws an error and disconnects the client.
   */
  private async handleHandshake(pluginVersion?: string): Promise<void> {
    if (!pluginVersion || !isVersionCompatible(pluginVersion, DAEMON_VERSION)) {
      const message = `Version mismatch: plugin v${pluginVersion ?? "unknown"}, daemon v${DAEMON_VERSION}. Update both to matching versions.`;

      this.sendError(message);
      this.send({ type: "daemonDisconnect" }); // stops the plugin's sync session
      this.close();

      log.error(`VERSION MISMATCH:`);
      log.error(
        `- Your Plugin version: ${pluginVersion ?? "unknown (needs update)"}`,
      );
      log.error(`- Your Daemon version: ${DAEMON_VERSION}`);
      log.error(`Make sure both are updated and using matching versions!`);
      if (!pluginVersion) {
        log.error(
          `If the Plugin is up to date but still shows "unknown", please open an issue.`,
        );
      }

      throw new Error(message);
    }

    if (!this.handshakeComplete) {
      this.handshakeComplete = true;
      if (this.handshakeHandler) {
        this.handshakeHandler();
      }
    }
    this.send({ type: "handshakeAck", version: DAEMON_VERSION });
  }

  /**
   * Register a handler for incoming Studio messages
   */
  public onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
  }

  /**
   * Register a handler that fires when a Studio client connects
   */
  public onConnection(handler: () => void): void {
    this.connectionHandler = handler;
  }

  /**
   * Register a handler that fires when Studio completes the handshake
   */
  public onHandshake(handler: () => void): void {
    this.handshakeHandler = handler;
    if (this.handshakeComplete) {
      handler();
    }
  }

  /**
   * Send a message to the connected Studio client
   */
  public send(message: DaemonMessage): boolean {
    if (!this.client || this.client.readyState !== WebSocket.OPEN) {
      log.warn("Cannot send message: no connected client");
      return false;
    }

    try {
      this.client.send(JSON.stringify(message));
      log.debug(`Sent: ${message.type}`);
      return true;
    } catch (error) {
      log.error("Failed to send message:", error);
      return false;
    }
  }

  /**
   * Send a patch to update a script's source in Studio
   */
  public patchScript(guid: string, source: string): boolean {
    return this.send({
      type: "patchScript",
      guid,
      source,
    });
  }

  /**
   * Tell Studio to create a new instance (script or folder)
   */
  public createInstance(
    className: string,
    name: string,
    parentPath: string[],
    source?: string,
  ): boolean {
    return this.send({
      type: "createInstance",
      className,
      name,
      parentPath,
      source,
    });
  }

  /**
   * Tell Studio to delete an instance by GUID or path
   */
  public deleteInstance(guid?: string, instancePath?: string[]): boolean {
    return this.send({
      type: "deleteInstance",
      guid,
      path: instancePath,
    });
  }

  /**
   * Tell Studio to move/rename an existing instance by GUID, preserving its
   * descendants (including non-script instances not represented on disk).
   */
  public moveInstance(
    guid: string,
    parentPath: string[],
    name: string,
    className?: string,
    source?: string,
  ): boolean {
    return this.send({
      type: "moveInstance",
      guid,
      parentPath,
      name,
      className,
      source,
    });
  }

  /**
   * Send an error message to Studio
   */
  public sendError(message: string): boolean {
    return this.send({
      type: "error",
      message,
    });
  }

  /**
   * Request a full snapshot from Studio
   */
  public requestSnapshot(options?: SnapshotRequestOptions): boolean {
    return this.send({
      type: "requestSnapshot",
      options,
    });
  }

  /**
   * Check if a client is connected
   */
  public isConnected(): boolean {
    return this.client !== null && this.client.readyState === WebSocket.OPEN;
  }

  /**
   * Close the server
   */
  public close(): void {
    for (const interval of this.pingIntervals.values()) {
      clearInterval(interval);
    }
    this.pingIntervals.clear();

    if (this.client) {
      this.client.close();
      this.client = null;
    }
    this.wss.close();
    log.info("WebSocket server closed.");
  }
}
