import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { writeFileSync } from "node:fs";

const endpoint = "http://192.168.1.99:9000/mcp";
const outputPath = "C:\\Users\\r_ratush\\Desktop\\CatMCP-backup-work\\all-tools-audit.json";
const node = "C:\\Program Files\\nodejs\\node.exe";
const proxy = "C:\\Users\\r_ratush\\AppData\\Local\\npm-cache\\_npx\\705d23756ff7dacc\\node_modules\\mcp-remote\\dist\\proxy.js";

class Client {
  constructor() {
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = [];
  }

  async start() {
    this.child = spawn(node, [proxy, endpoint, "--allow-http"], {
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }
      const pending = this.pending.get(message.id);
      if (pending) {
        this.pending.delete(message.id);
        pending.resolve(message);
      }
    });
    createInterface({ input: this.child.stderr }).on("line", (line) => {
      this.stderr.push(line);
    });
    await this.request("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "catmcp-full-audit", version: "1.0" },
    }, 15000);
    this.notify("notifications/initialized", {});
  }

  notify(method, params) {
    this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
  }

  request(method, params, timeoutMs = 10000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout after ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(id, {
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        },
      });
      this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  }

  async call(name, args = {}, timeoutMs = 10000) {
    return this.request("tools/call", { name, arguments: args }, timeoutMs);
  }

  stop() {
    if (!this.child) return;
    this.child.stdin.end();
    setTimeout(() => this.child.kill(), 500).unref();
  }
}

function decoded(message) {
  if (message.error) return { error: message.error };
  const content = message.result?.content ?? [];
  return {
    isError: Boolean(message.result?.isError),
    content: content.map((item) => {
      if (item.type === "image" || item.data) {
        return {
          type: item.type ?? "image",
          mimeType: item.mimeType,
          dataLength: item.data?.length ?? 0,
        };
      }
      if (typeof item.text === "string") {
        try {
          return { type: item.type ?? "text", value: JSON.parse(item.text) };
        } catch {
          return { type: item.type ?? "text", value: item.text };
        }
      }
      return item;
    }),
  };
}

function firstValue(message) {
  return decoded(message).content?.[0]?.value;
}

const client = new Client();
const results = [];
const tempDir = "/var/mobile/catmcp-audit-temp";
const tempSubdir = `${tempDir}/subdir`;
const tempFile = `${tempDir}/probe.txt`;
const probeText = `CatMCP audit ${new Date().toISOString()}`;

async function test(name, args = {}, timeoutMs = 10000) {
  const started = Date.now();
  try {
    const response = await client.call(name, args, timeoutMs);
    const result = {
      name,
      args,
      durationMs: Date.now() - started,
      status: response.error || response.result?.isError ? "error" : "ok",
      response: decoded(response),
    };
    results.push(result);
    console.log(`${result.status.toUpperCase()} ${name} ${result.durationMs}ms`);
    return response;
  } catch (error) {
    const result = {
      name,
      args,
      durationMs: Date.now() - started,
      status: "timeout",
      error: String(error.message ?? error),
    };
    results.push(result);
    console.log(`TIMEOUT ${name} ${result.durationMs}ms`);
    return null;
  }
}

let initialBrightness;
let initialVolume;
let initialAssistive;
let initialControlCenter;
let initialOrientation;

try {
  await client.start();

  await test("self_state");
  await test("device_battery");
  await test("device_ip");
  await test("device_name");
  await test("screen_size");
  await test("screen_snapshot", { scale: 15, quality: 50 }, 15000);

  await test("app_list", {}, 20000);
  await test("app_bundle_path", { id: "com.apple.Preferences" });
  await test("app_data_path", { id: "com.apple.Preferences" });
  await test("app_run", { id: "com.apple.Preferences" });
  await new Promise((resolve) => setTimeout(resolve, 1500));
  await test("app_front");
  await test("app_kill", { id: "com.apple.Preferences" });
  await test("app_uninstall", { id: "com.ratush.catmcp.audit.nonexistent" });

  await test("dir_create", { path: tempDir });
  await test("dir_create", { path: tempSubdir });
  await test("file_write", {
    path: tempFile,
    data: Buffer.from(probeText).toString("base64"),
  });
  await test("file_read", { path: tempFile });
  await test("dir_list", { path: tempDir });
  await test("file_remove", { path: tempFile });
  await test("dir_remove", { path: tempSubdir });
  await test("dir_remove", { path: tempDir });

  await test("system_shell", {
    command: "printf CATMCP_AUDIT_OK; echo; id; printf PATH=; echo $PATH",
  });

  initialBrightness = firstValue(await test("system_brightness_get"))?.brightness;
  if (Number.isFinite(initialBrightness)) {
    await test("system_brightness_set", { brightness: Math.round(initialBrightness) });
  }
  initialVolume = firstValue(await test("system_volume_get"))?.volume;
  if (Number.isFinite(initialVolume)) {
    await test("system_volume_set", { volume: Math.round(initialVolume) });
  }
  initialAssistive = firstValue(await test("system_assistive_touch_visible"))?.visible;
  initialControlCenter = firstValue(await test("system_control_center_visible"))?.visible;
  initialOrientation = firstValue(await test("system_orientation_locked"))?.locked;

  await test("system_copy", { text: probeText });
  await test("system_open_url", { url: "prefs:root=General&path=About" });
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await test("system_input", { text: probeText });

  if (typeof initialAssistive === "boolean") {
    await test("system_toggle_assistive_touch", { on: !initialAssistive });
    await test("system_toggle_assistive_touch", { on: initialAssistive });
  }
  if (typeof initialControlCenter === "boolean") {
    await test("system_toggle_control_center", { on: !initialControlCenter });
    await test("system_toggle_control_center", { on: initialControlCenter });
  }
  if (typeof initialOrientation === "boolean") {
    await test("system_toggle_orientation_lock", { on: !initialOrientation });
    await test("system_toggle_orientation_lock", { on: initialOrientation });
  }

  await test("app_run", { id: "com.apple.Preferences" });
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await test("key_down", { code: "Shift" });
  await test("key_up", { code: "Shift" });
  await test("key_click", { code: "Home" });
  await test("touch_click", { x: 0.5, y: 0.05 });
  await test("touch_down", { finger: 0, x: 0.5, y: 0.05 });
  await test("touch_move", { finger: 0, x: 0.52, y: 0.06 });
  await test("touch_up", { finger: 0 });
  await test("touch_swipe", { x1: 0.5, y1: 0.35, x2: 0.5, y2: 0.25, duration: 250 });
  await test("touch_long_press", { x: 0.5, y: 0.05, duration: 300 });
} finally {
  try {
    if (Number.isFinite(initialBrightness)) {
      await client.call("system_brightness_set", { brightness: Math.round(initialBrightness) }, 5000);
    }
    if (Number.isFinite(initialVolume)) {
      await client.call("system_volume_set", { volume: Math.round(initialVolume) }, 5000);
    }
    if (typeof initialAssistive === "boolean") {
      await client.call("system_toggle_assistive_touch", { on: initialAssistive }, 5000);
    }
    if (typeof initialControlCenter === "boolean") {
      await client.call("system_toggle_control_center", { on: initialControlCenter }, 5000);
    }
    if (typeof initialOrientation === "boolean") {
      await client.call("system_toggle_orientation_lock", { on: initialOrientation }, 5000);
    }
    await client.call("system_shell", {
      command: `rm -rf '${tempDir}'`,
    }, 5000);
  } catch {
    // Best-effort restore; SSH verification follows.
  }
  client.stop();
  writeFileSync(outputPath, JSON.stringify({
    endpoint,
    finishedAt: new Date().toISOString(),
    results,
    stderrTail: client.stderr.slice(-100),
  }, null, 2));
}
