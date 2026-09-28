import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createServer, type Server } from "node:http";
import { WebSocket } from "ws";
import { IPCServer } from "../ipc/server.js";
import {
  StudioOutputFormatter,
  isStudioOutputMessage,
} from "../studioOutput.js";
import type { StudioOutputMessage } from "../ipc/messages.js";

function waitForOpen(webSocket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    webSocket.once("open", resolve);
    webSocket.once("error", reject);
  });
}

const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

/** Build a relayed message logged at 00:16:28.796 local time. */
function output(
  message: string,
  messageType: string,
  source: StudioOutputMessage["source"] = "server",
): StudioOutputMessage {
  return {
    type: "studioOutput",
    message,
    messageType,
    source,
    timestamp: new Date(2026, 0, 1, 0, 16, 28, 796).getTime(),
  };
}

test("rewrites Studio script locations using the sourcemap", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "azul-output-"));
  const sourcemapPath = path.join(directory, "sourcemap.json");

  try {
    fs.writeFileSync(
      sourcemapPath,
      JSON.stringify({
        name: "Game",
        className: "DataModel",
        children: [
          {
            name: "ServerScriptService",
            className: "ServerScriptService",
            children: [
              {
                name: "MyModule",
                className: "Script",
                filePaths: ["sync\\ServerScriptService\\MyModule.server.luau"],
              },
            ],
          },
        ],
      }),
    );

    const formatter = new StudioOutputFormatter(sourcemapPath);
    assert.equal(
      formatter.format(
        output(
          "Script 'game.ServerScriptService.MyModule', Line 42 - attempt to index nil",
          "MessageOutput",
        ),
      ),
      `${DIM}  00:16:28.796${RESET}  Script sync/ServerScriptService/MyModule.server.luau:42 - attempt to index nil  ${DIM}-  Server${RESET}`,
    );
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("colors warnings without changing unresolved Studio locations", () => {
  const formatter = new StudioOutputFormatter("missing-sourcemap.json");
  assert.equal(
    formatter.format(
      output(
        "Script 'game.ServerScriptService.Missing', Line 7 - warning",
        "MessageWarning",
        "client",
      ),
    ),
    `${DIM}  00:16:28.796${RESET}  \x1b[33mScript 'game.ServerScriptService.Missing', Line 7 - warning${RESET}  ${DIM}-  Client${RESET}`,
  );
});

test("strips control characters from relayed messages", () => {
  const formatter = new StudioOutputFormatter("missing-sourcemap.json");
  assert.equal(
    formatter.format(output("server\x1b[2J output", "MessageOutput")),
    `${DIM}  00:16:28.796${RESET}  server[2J output  ${DIM}-  Server${RESET}`,
  );
});

test("rejects malformed output messages", () => {
  assert.equal(isStudioOutputMessage(output("ok", "MessageOutput")), true);
  assert.equal(
    isStudioOutputMessage({ type: "studioOutput", message: 42 }),
    false,
  );
});

async function startServer(): Promise<{
  httpServer: Server;
  ipcServer: IPCServer;
  url: string;
}> {
  const httpServer = createServer();
  await new Promise<void>((resolve) => httpServer.listen(0, resolve));
  const address = httpServer.address();
  assert.ok(address && typeof address !== "string");

  const ipcServer = new IPCServer(undefined, httpServer, {
    requestSnapshotOnConnect: false,
  });
  return { httpServer, ipcServer, url: `ws://127.0.0.1:${address.port}` };
}

async function stopServer(httpServer: Server, ipcServer: IPCServer) {
  await ipcServer.close();
  await new Promise<void>((resolve) => httpServer.close(() => resolve()));
}

test("accepts playtest output without replacing the Studio connection", async () => {
  const { httpServer, ipcServer, url } = await startServer();
  const studioClient = new WebSocket(url);

  try {
    await waitForOpen(studioClient);

    const receivedOutput = new Promise<string>((resolve) => {
      ipcServer.onMessage((message) => {
        if (message.type === "studioOutput" && message.source === "server") {
          resolve(message.message);
        }
      });
    });
    const outputClient = new WebSocket(`${url}/studio-output`);
    await waitForOpen(outputClient);
    outputClient.send(
      JSON.stringify({
        type: "studioOutput",
        message: "server output",
        messageType: "MessageOutput",
        source: "server",
        timestamp: Date.now(),
      }),
    );

    assert.equal(await receivedOutput, "server output");
    assert.equal(ipcServer.isConnected(), true);
    assert.equal(ipcServer.send({ type: "pong" }), true);
    outputClient.close();
  } finally {
    studioClient.close();
    await stopServer(httpServer, ipcServer);
  }
});

test("keeps the new Studio connection when a replaced one closes", async () => {
  const { httpServer, ipcServer, url } = await startServer();
  const oldClient = new WebSocket(url);
  let newClient: WebSocket | undefined;

  try {
    await waitForOpen(oldClient);
    const oldClosed = new Promise<void>((resolve) =>
      oldClient.once("close", () => resolve()),
    );
    newClient = new WebSocket(url);
    await waitForOpen(newClient);
    await oldClosed;
    // Let the server process the old socket's close event
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.equal(ipcServer.isConnected(), true);
  } finally {
    // Terminate here so a failed assertion can't leave the server waiting on an open socket
    newClient?.terminate();
    await stopServer(httpServer, ipcServer);
  }
});

test("rejects playtest output while Studio is not connected", async () => {
  const { httpServer, ipcServer, url } = await startServer();

  try {
    const outputClient = new WebSocket(`${url}/studio-output`);
    const closed = new Promise<void>((resolve) => {
      outputClient.once("close", () => resolve());
      outputClient.once("error", () => resolve());
    });
    await closed;
    assert.equal(ipcServer.isConnected(), false);
  } finally {
    await stopServer(httpServer, ipcServer);
  }
});
