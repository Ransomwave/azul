import { WebSocketServer, WebSocket } from "ws";
import { log } from "../util/log.js";
import type { StudioMessage, DaemonMessage } from "./messages.js";

export type MessageHandler = (message: StudioMessage) => void;

export class IPCServer {
  private wss: WebSocketServer;
  private client: WebSocket | null = null;
  private messageHandler: MessageHandler | null = null;
  private port: number;

  constructor(port: number = 8080) {
    this.port = port;
    this.wss = new WebSocketServer({ port });
    this.setupServer();
  }

  private setupServer(): void {
    this.wss.on("connection", (ws) => {
      log.info("Studio client connected");

      // Disconnect previous client if exists
      if (this.client) {
        log.warn("Disconnecting previous client");
        this.client.close();
      }

      this.client = ws;

      ws.on("message", (data) => {
        try {
          const message: StudioMessage = JSON.parse(data.toString());
          log.debug(`Received: ${message.type}`);

          if (this.messageHandler) {
            this.messageHandler(message);
          }
        } catch (error) {
          log.error("Failed to parse message:", error);
          this.sendError("Invalid JSON message");
        }
      });

      ws.on("close", () => {
        log.info("Studio client disconnected");
        this.client = null;
      });

      ws.on("error", (error) => {
        log.error("WebSocket error:", error);
      });

      // Request initial snapshot
      this.send({ type: "requestSnapshot" });
    });

    this.wss.on("listening", () => {
      log.success(`WebSocket server listening on port ${this.port}`);
    });

    this.wss.on("error", (error) => {
      log.error("WebSocket server error:", error);
    });
  }

  /**
   * Register a handler for incoming Studio messages
   */
  public onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
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
  public requestSnapshot(): boolean {
    return this.send({
      type: "requestSnapshot",
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
    if (this.client) {
      this.client.close();
    }
    this.wss.close();
    log.info("WebSocket server closed");
  }
}
