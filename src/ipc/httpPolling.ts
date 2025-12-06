/**
 * HTTP endpoints for plugin polling compatibility
 */

import { IncomingMessage, ServerResponse } from "http";
import { log } from "../util/log.js";

interface PollingClient {
  id: string;
  messageQueue: any[];
  lastPoll: number;
}

/**
 * Manages HTTP polling for Roblox Studio plugin compatibility
 */
export class HttpPollingServer {
  private clients: Map<string, PollingClient> = new Map();
  private messageHandler: ((message: any, clientId: string) => void) | null =
    null;

  /**
   * Handle HTTP request
   */
  public handleRequest(req: IncomingMessage, res: ServerResponse): boolean {
    const url = new URL(req.url || "", `http://${req.headers.host}`);

    // Enable CORS
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(200);
      res.end();
      return true;
    }

    switch (url.pathname) {
      case "/connect":
        return this.handleConnect(req, res);
      case "/send":
        return this.handleSend(req, res);
      case "/poll":
        return this.handlePoll(req, res, url);
      case "/disconnect":
        return this.handleDisconnect(req, res);
      default:
        return false;
    }
  }

  /**
   * Handle connect request
   */
  private handleConnect(_req: IncomingMessage, res: ServerResponse): boolean {
    const clientId = this.generateClientId();

    this.clients.set(clientId, {
      id: clientId,
      messageQueue: [],
      lastPoll: Date.now(),
    });

    log.info(`HTTP client connected: ${clientId}`);

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ clientId }));
    return true;
  }

  /**
   * Handle send request
   */
  private handleSend(req: IncomingMessage, res: ServerResponse): boolean {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", () => {
      try {
        const data = JSON.parse(body);
        const { clientId, message } = data;

        if (this.messageHandler) {
          this.messageHandler(message, clientId);
        }

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
      } catch (error) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
      }
    });

    return true;
  }

  /**
   * Handle poll request
   */
  private handlePoll(
    _req: IncomingMessage,
    res: ServerResponse,
    url: URL
  ): boolean {
    const clientId = url.searchParams.get("clientId");

    if (!clientId || !this.clients.has(clientId)) {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Client not found" }));
      return true;
    }

    const client = this.clients.get(clientId)!;
    client.lastPoll = Date.now();

    const messages = client.messageQueue.splice(0); // Take all messages

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(messages));
    return true;
  }

  /**
   * Handle disconnect request
   */
  private handleDisconnect(req: IncomingMessage, res: ServerResponse): boolean {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", () => {
      try {
        const data = JSON.parse(body);
        const { clientId } = data;

        if (clientId && this.clients.has(clientId)) {
          this.clients.delete(clientId);
          log.info(`HTTP client disconnected: ${clientId}`);
        }

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
      } catch (error) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
      }
    });

    return true;
  }

  /**
   * Send message to a specific client
   */
  public sendToClient(clientId: string, message: any): boolean {
    const client = this.clients.get(clientId);
    if (!client) {
      return false;
    }

    client.messageQueue.push(message);
    return true;
  }

  /**
   * Broadcast message to all clients
   */
  public broadcast(message: any): void {
    for (const client of this.clients.values()) {
      client.messageQueue.push(message);
    }
  }

  /**
   * Set message handler
   */
  public onMessage(handler: (message: any, clientId: string) => void): void {
    this.messageHandler = handler;
  }

  /**
   * Clean up stale clients
   */
  public cleanupStaleClients(timeoutMs: number = 60000): void {
    const now = Date.now();
    for (const [id, client] of this.clients.entries()) {
      if (now - client.lastPoll > timeoutMs) {
        this.clients.delete(id);
        log.info(`Removed stale HTTP client: ${id}`);
      }
    }
  }

  /**
   * Generate unique client ID
   */
  private generateClientId(): string {
    return `client_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Get active client count
   */
  public getClientCount(): number {
    return this.clients.size;
  }
}
