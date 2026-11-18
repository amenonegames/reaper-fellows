#!/usr/bin/env node
// MCP server that lets Claude act inside REAPER through Claude Panel.
//
// Claude Code starts this process (stdio transport, newline-delimited JSON-RPC).
// It has no connection to REAPER of its own: every tool call is written as a
// file into a bridge folder, the panel running inside REAPER picks it up,
// carries it out and writes the answer back as another file.
//
//   request   <bridge>/request.json          {"id": "...", "tool": "...", "args": {...}}
//   response  <bridge>/response_<id>.json    {"ok": true|false, "text": "..."}
//
// Usage: node reaper_mcp_server.js <bridge folder>
// No dependencies; any Node.js 16 or newer.

"use strict";

const fs = require("fs");
const path = require("path");

const VERSION = "0.2.0";
const bridgeDir = process.argv[2];
const POLL_MS = 40;
// The panel may be waiting for the person (a question, or an edit to approve),
// so the limit is long. If the panel goes away, Claude Code is stopped with it.
const TIMEOUT_MS = 30 * 60 * 1000;

const TOOLS = [
  {
    name: "get_selection",
    description:
      "Read the current state of the REAPER project: tempo, cursor, time selection, the selected tracks " +
      "(volume, pan, FX chain), the selected items and their MIDI notes, and the notes selected in the MIDI " +
      "editor. Returns the same kind of text as the <reaper_context> block, taken fresh. Use it after a " +
      "change to check the result, or when the person may have changed the selection.",
    inputSchema: {
      type: "object",
      properties: {
        all_tracks: { type: "boolean", description: "Also list every track in the project with its FX chain." },
        markers: { type: "boolean", description: "Also list markers and regions." },
      },
    },
  },
  {
    name: "find_api",
    description:
      "Search the names of the ReaScript API functions that exist in this REAPER installation (including " +
      "installed extensions such as SWS or js_ReaScriptAPI). Returns matching function names, not their " +
      "signatures. Use it before run_lua when you are not certain a function exists under that exact name.",
    inputSchema: {
      type: "object",
      properties: {
        filter: { type: "string", description: "Case-insensitive text the function name must contain, e.g. \"MIDI_Insert\" or \"TrackFX\"." },
      },
      required: ["filter"],
    },
  },
  {
    name: "run_lua",
    description:
      "Run a ReaScript written in Lua inside REAPER, on the open project. This is how you change the project " +
      "or read anything get_selection does not cover. The whole script is one undo step named after " +
      "`description`. `print(...)` output and the script's return values come back as the result; on an error " +
      "you get the message and line. The script runs to completion on REAPER's main thread: do not use " +
      "reaper.defer, message boxes, input dialogs or anything that waits for the person. Scripts that run " +
      "longer than 10 seconds are stopped. io, os (except time/date/clock), require and reaper.ExecProcess " +
      "are not available.",
    inputSchema: {
      type: "object",
      properties: {
        description: { type: "string", description: "A few words on what the script does, in the person's language. Shown in the panel and used as the undo name." },
        code: { type: "string", description: "The complete Lua script." },
      },
      required: ["description", "code"],
    },
  },
  {
    name: "ask_user",
    description:
      "Ask the person a question in the panel and wait for the answer. With `options` the panel shows buttons " +
      "(pick one) or, with multi=true, checkboxes (pick several); without options they type the answer. The " +
      "person can always type a free reply instead of picking. Use it when the answer changes what you do " +
      "next: before a destructive or large change, or when the request has more than one reasonable reading.",
    inputSchema: {
      type: "object",
      properties: {
        question: { type: "string", description: "The question, in the person's language." },
        options: { type: "array", items: { type: "string" }, description: "2 to 6 short choices. Omit for a free-text answer." },
        multi: { type: "boolean", description: "true to let the person pick several options." },
      },
      required: ["question"],
    },
  },
];

function log(message) {
  process.stderr.write("[reaper-mcp] " + message + "\n");
}

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

let nextId = 1;

// Hands one tool call to the panel and waits for its answer.
async function callPanel(tool, args) {
  if (!bridgeDir) {
    return { ok: false, text: "The server was started without a bridge folder." };
  }
  const id = String(process.pid) + "_" + String(nextId++);
  const requestPath = path.join(bridgeDir, "request.json");
  const tmpPath = path.join(bridgeDir, "request.tmp");
  const responsePath = path.join(bridgeDir, "response_" + id + ".json");

  try {
    fs.mkdirSync(bridgeDir, { recursive: true });
    // Written under another name first so the panel never reads half a file
    fs.writeFileSync(tmpPath, JSON.stringify({ id, tool, args: args || {} }), "utf8");
    fs.renameSync(tmpPath, requestPath);
  } catch (err) {
    return { ok: false, text: "Could not write the request for REAPER: " + err.message };
  }

  const deadline = Date.now() + TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (fs.existsSync(responsePath)) {
      // The panel renames the finished file into place, but give a file that is
      // still being flushed one more round rather than failing on it.
      try {
        const response = JSON.parse(fs.readFileSync(responsePath, "utf8"));
        try { fs.unlinkSync(responsePath); } catch (err) { /* left behind, harmless */ }
        return { ok: response.ok === true, text: String(response.text === undefined ? "" : response.text) };
      } catch (err) {
        await sleep(POLL_MS);
        continue;
      }
    }
    await sleep(POLL_MS);
  }
  try { fs.unlinkSync(requestPath); } catch (err) { /* already taken */ }
  return { ok: false, text: "REAPER did not answer. Is the Claude Panel window still open?" };
}

// Tool calls are carried out one at a time: the bridge has a single request slot.
let queue = Promise.resolve();

function handleToolCall(id, params) {
  const name = params && params.name;
  if (!TOOLS.some((t) => t.name === name)) {
    send({ jsonrpc: "2.0", id, error: { code: -32602, message: "Unknown tool: " + name } });
    return;
  }
  queue = queue.then(async () => {
    const result = await callPanel(name, params.arguments);
    send({
      jsonrpc: "2.0",
      id,
      result: { content: [{ type: "text", text: result.text }], isError: !result.ok },
    });
  }).catch((err) => {
    send({ jsonrpc: "2.0", id, error: { code: -32603, message: String(err && err.message) } });
  });
}

function handleMessage(message) {
  const { id, method, params } = message;
  const isRequest = id !== undefined && id !== null;
  switch (method) {
    case "initialize":
      send({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: (params && params.protocolVersion) || "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "reaper", version: VERSION },
        },
      });
      break;
    case "ping":
      send({ jsonrpc: "2.0", id, result: {} });
      break;
    case "tools/list":
      send({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
      break;
    case "tools/call":
      handleToolCall(id, params);
      break;
    default:
      // Notifications (no id) need no answer; unknown requests get an error.
      if (isRequest) {
        send({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found: " + method } });
      }
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      handleMessage(JSON.parse(line));
    } catch (err) {
      log("could not handle a message: " + err.message);
    }
  }
});
process.stdin.on("end", () => process.exit(0));

log("started, bridge folder: " + bridgeDir);
