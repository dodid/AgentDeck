#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const pluginRoot = path.join(repoRoot, "integrations/openclaw");
const openclaw = process.env.AGENTDECK_OPENCLAW_BIN
  ?? path.join(pluginRoot, "node_modules/.bin/openclaw");
const operatorInstallIndex = path.join(os.homedir(), ".openclaw/plugins/installs.json");
if (process.env.GITHUB_ACTIONS !== "true" && fs.existsSync(operatorInstallIndex)) {
  throw new Error(
    `Refusing to run beside an operator OpenClaw install index (${operatorInstallIndex}). `
    + "Run this lifecycle harness on an ephemeral CI host.",
  );
}
const root = fs.mkdtempSync(path.join(os.tmpdir(), "agentdeck-openclaw-lifecycle-"));
const home = path.join(root, "home");
const artifacts = process.env.AGENTDECK_LIFECYCLE_ARTIFACTS
  ?? path.join(root, "artifacts");
const npmCache = path.join(root, "npm-cache");
const env = {
  ...process.env,
  OPENCLAW_HOME: home,
  OPENCLAW_STATE_DIR: path.join(home, ".openclaw"),
  OPENCLAW_CONFIG_PATH: path.join(home, ".openclaw/openclaw.json"),
  NPM_CONFIG_CACHE: npmCache,
  NPM_CONFIG_AUDIT: "false",
  NPM_CONFIG_FUND: "false",
  NPM_CONFIG_UPDATE_NOTIFIER: "false",
  NO_COLOR: "1",
  CI: "1",
};

fs.mkdirSync(home, { recursive: true });
fs.mkdirSync(artifacts, { recursive: true });

function run(command, args, options = {}) {
  const output = execFileSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env,
    encoding: "utf8",
    stdio: options.capture === false ? "inherit" : ["ignore", "pipe", "pipe"],
  });
  return output ?? "";
}

function runOpenClaw(args, options) {
  return run(openclaw, args, options);
}

function pack(directory) {
  const raw = run("npm", ["pack", "--json", "--pack-destination", root], { cwd: directory });
  const result = JSON.parse(raw);
  assert.equal(result.length, 1, "npm pack should create exactly one package");
  return path.join(root, result[0].filename);
}

function installedPackageCandidates() {
  return [
    path.join(home, ".openclaw/extensions/r2-relay-channel/package.json"),
  ];
}

function installedPackagePath() {
  const found = installedPackageCandidates().find(fs.existsSync);
  assert.ok(found, `installed plugin package not found under ${home}`);
  return found;
}

function inspectPlugin() {
  const raw = runOpenClaw(["plugins", "inspect", "r2-relay-channel", "--json"]);
  const parsed = JSON.parse(raw);
  assert.equal(parsed.plugin?.id, "r2-relay-channel");
  assert.notEqual(parsed.plugin?.status, "error");
  return parsed;
}

function install(packagePath) {
  runOpenClaw(["plugins", "install", packagePath, "--force"], { capture: false });
  inspectPlugin();
}

try {
  run("npm", ["run", "build"], { cwd: pluginRoot, capture: false });
  const candidatePackage = pack(pluginRoot);

  const previousRoot = path.join(root, "previous");
  fs.mkdirSync(previousRoot, { recursive: true });
  run("tar", ["-xzf", candidatePackage, "-C", previousRoot]);
  const previousPackageJSON = path.join(previousRoot, "package/package.json");
  const previousPackage = JSON.parse(fs.readFileSync(previousPackageJSON, "utf8"));
  previousPackage.version = "0.0.0-lifecycle";
  fs.writeFileSync(previousPackageJSON, `${JSON.stringify(previousPackage, null, 2)}\n`);
  const previousArtifact = pack(path.dirname(previousPackageJSON));

  install(previousArtifact);
  assert.equal(JSON.parse(fs.readFileSync(installedPackagePath(), "utf8")).version, "0.0.0-lifecycle");

  const sidecar = path.join(home, ".openclaw/r2relay.config.json");
  fs.mkdirSync(path.dirname(sidecar), { recursive: true });
  fs.writeFileSync(sidecar, `${JSON.stringify({
    enabled: true,
    endpoint: "http://127.0.0.1:9000",
    bucket: "lifecycle",
    accessKeyId: "test-access",
    secretAccessKey: "test-secret",
    serverId: "lifecycle-openclaw",
  }, null, 2)}\n`);
  runOpenClaw([
    "config", "set", "channels.r2-relay-channel",
    JSON.stringify({ enabled: true, configFile: sidecar }), "--strict-json",
  ]);
  const checkpoint = path.join(home, ".openclaw/plugins/r2-relay-channel/default.json");
  fs.mkdirSync(path.dirname(checkpoint), { recursive: true });
  fs.writeFileSync(checkpoint, '{"lastHeadKey":"head-before-upgrade"}\n');

  install(candidatePackage);
  const candidateVersion = JSON.parse(fs.readFileSync(path.join(pluginRoot, "package.json"), "utf8")).version;
  assert.equal(JSON.parse(fs.readFileSync(installedPackagePath(), "utf8")).version, candidateVersion);
  assert.ok(fs.readFileSync(sidecar, "utf8").includes("lifecycle-openclaw"), "sidecar was not preserved");
  assert.ok(fs.readFileSync(checkpoint, "utf8").includes("head-before-upgrade"), "checkpoint was not preserved");
  runOpenClaw(["config", "validate"]);

  runOpenClaw(["plugins", "uninstall", "r2-relay-channel", "--force"]);
  assert.ok(installedPackageCandidates().every((candidate) => !fs.existsSync(candidate)));
  assert.ok(fs.existsSync(sidecar), "uninstall should not delete operator-owned relay configuration");
  assert.ok(fs.existsSync(checkpoint), "uninstall should not delete relay checkpoint state");

  install(candidatePackage);
  runOpenClaw(["config", "validate"]);

  const report = {
    openclawVersion: runOpenClaw(["--version"]).trim(),
    pluginVersion: candidateVersion,
    phases: ["fresh-install", "upgrade", "config-preservation", "checkpoint-preservation", "uninstall", "reinstall"],
  };
  fs.writeFileSync(path.join(artifacts, "openclaw-lifecycle.json"), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  fs.writeFileSync(path.join(artifacts, "openclaw-lifecycle-error.txt"), `${error?.stack ?? error}\n`);
  throw error;
} finally {
  if (!process.env.AGENTDECK_KEEP_LIFECYCLE_HOME) {
    fs.rmSync(root, { recursive: true, force: true });
  } else {
    console.log(`Lifecycle home retained at ${root}`);
  }
}
