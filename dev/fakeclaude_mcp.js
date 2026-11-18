#!/usr/bin/env node
// Stand-in for the Claude Code CLI that really speaks MCP: it starts the server
// named in --mcp-config, calls the tools in a fixed order and reports what came
// back as stream-json, the way the panel expects it from `claude -p`.
"use strict";
const fs = require("fs");
const { spawn } = require("child_process");

const argv = process.argv.slice(2);
if (argv[0] === "--version") { console.log("9.9.9 (Fake Claude MCP)"); process.exit(0); }
const configPath = argv[argv.indexOf("--mcp-config") + 1];
const prompt = fs.readFileSync(0, "utf8");
fs.writeFileSync(__dirname + "/last_args.txt", argv.join(" "));
fs.writeFileSync(__dirname + "/last_prompt.txt", prompt);

const emit = (o) => process.stdout.write(JSON.stringify(o) + "\n");
const say = (text) => emit({ type: "assistant", message: { content: [{ type: "text", text }] } });
const sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

const server = JSON.parse(fs.readFileSync(configPath, "utf8")).mcpServers.reaper;
const child = spawn(server.command, server.args, { stdio: ["pipe", "pipe", "inherit"] });
let buf = "", nextId = 1;
const waiting = new Map();
child.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const msg = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
    if (waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
  }
});
const rpc = (method, params) => new Promise((resolve) => {
  const id = nextId++; waiting.set(id, resolve);
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
});
const tool = async (name, args) => {
  const r = await rpc("tools/call", { name, arguments: args });
  return (r.result.isError ? "ERR " : "OK ") + r.result.content[0].text;
};

(async () => {
  emit({ type: "system", subtype: "init", session_id: sid });
  const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "fake", version: "1" } });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const list = await rpc("tools/list", {});
  const out = ["server " + init.result.serverInfo.name + ", tools: " + list.result.tools.map((t) => t.name).join(" ")];

  // text streamed before a tool call, whose complete message arrives late
  emit({ type: "stream_event", event: { type: "message_start" } });
  emit({ type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text: "Let me look." } } });

  const steps = prompt.includes("CONFIRM")
    ? [["run_lua", { description: "count tracks", code: "return reaper.CountTracks(0)" }]]
    : [
      ["get_selection", { markers: true }],
      ["find_api", { filter: "counttrack" }],
      ["run_lua", { description: "count tracks", code: "print('tracks', reaper.CountTracks(0))\nreturn 7, {a = 1}" }],
      ["run_lua", { description: "broken", code: "local x = nil\nreturn x.y" }],
      ["run_lua", { description: "syntax", code: "this is not lua" }],
      ["run_lua", { description: "blocked api", code: "reaper.ExecProcess('x', 0)" }],
      ["run_lua", { description: "no io", code: "return io.open('x')" }],
      ["ask_user", { question: "Which section?", options: ["Verse", "Chorus"], multi: false }],
      ["ask_user", { question: "Name it?" }],
      ["nope", {}],
    ];
  for (const [name, args] of steps) {
    if (name === "nope") {
      const r = await rpc("tools/call", { name, arguments: args });
      out.push("nope -> " + (r.error ? "error " + r.error.code : "no error"));
    } else {
      const text = await tool(name, args);
      out.push(name + " -> " + text.replace(/\n/g, " | ").slice(0, 230));
    }
    if (name === "get_selection") say("Let me look.");   // the late complete message
  }
  say(out.join("\n"));
  emit({ type: "result", subtype: "success", is_error: false, result: "done", session_id: sid });
  child.stdin.end();
})();
