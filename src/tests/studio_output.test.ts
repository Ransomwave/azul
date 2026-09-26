import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createServer } from "node:http";
import { WebSocket } from "ws";
import { IPCServer } from "../ipc/server.js";
import { StudioOutputFormatter } from "../studioOutput.js";

function waitForOpen(webSocket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    webSocket.once("open", resolve);
    webSocket.once("error", reject);
  });
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
                filePaths: [
                  "sync\\ServerScriptService\\MyModule.server.luau",
                ],
              },
            ],
          },
        ],
      }),
    );

    const formatter = new StudioOutputFormatter(sourcemapPath);
    assert.equal(
      formatter.format(
        "Script 'game.ServerScriptService.MyModule', Line 42 - attempt to index nil",
        "MessageOutput",
      ),
      "Script sync/ServerScriptService/MyModule.server.luau:42 - attempt to index nil",
    );
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("colors warnings without changing unresolved Studio locations", () => {
  const formatter = new StudioOutputFormatter("missing-sourcemap.json");
  assert.equal(
    formatter.format(
      "Script 'game.ServerScriptService.Missing', Line 7 - warning",
      "MessageWarning",
    ),
    "\x1b[33mScript 'game.ServerScriptService.Missing', Line 7 - warning\x1b[0m",
  );
});

test("accepts playtest output without replacing the Studio connection", async () => {
  const httpServer = createServer();
  await new Promise<void>((resolve) => httpServer.listen(0, resolve));
  const address = httpServer.address();
  assert.ok(address && typeof address !== "string");

  const ipcServer = new IPCServer(undefined, httpServer, {
    requestSnapshotOnConnect: false,
  });
  ipcServer.setOutputSessionId("test-session");
  const studioClient = new WebSocket(`ws://127.0.0.1:${address.port}`);

  try {
    await waitForOpen(studioClient);

    const receivedOutput = new Promise<void>((resolve) => {
      ipcServer.onMessage((message) => {
        if (message.type === "studioOutput" && message.source === "server") {
          resolve();
        }
      });
    });
    const outputClient = new WebSocket(
      `ws://127.0.0.1:${address.port}/studio-output?sessionId=test-session`,
    );
    await waitForOpen(outputClient);
    outputClient.send(
      JSON.stringify({
        type: "studioOutput",
        sessionId: "test-session",
        message: "server output",
        messageType: "MessageOutput",
        source: "server",
      }),
    );

    await receivedOutput;
    assert.equal(ipcServer.isConnected(), true);
    assert.equal(ipcServer.send({ type: "pong" }), true);
    outputClient.close();
  } finally {
    studioClient.close();
    await ipcServer.close();
    await new Promise<void>((resolve) => httpServer.close(() => resolve()));
  }
});
