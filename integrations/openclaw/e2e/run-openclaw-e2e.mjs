#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";
import { RelayTestClient, waitFor } from "./relay-test-client.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginRoot = path.resolve(__dirname, "..");

const endpoint = process.env.R2_RELAY_E2E_ENDPOINT ?? "http://127.0.0.1:9000";
const bucket = process.env.R2_RELAY_E2E_BUCKET ?? `agentdeck-e2e-${process.env.GITHUB_RUN_ID ?? Date.now()}`;
const accessKeyId = process.env.R2_RELAY_E2E_ACCESS_KEY_ID ?? "minioadmin";
const secretAccessKey = process.env.R2_RELAY_E2E_SECRET_ACCESS_KEY ?? "minioadmin";
const serverId = process.env.R2_RELAY_E2E_SERVER_ID ?? `ci-openclaw-${process.env.GITHUB_RUN_ID ?? Date.now()}`;
const clientPeer = process.env.R2_RELAY_E2E_CLIENT_PEER ?? `ci-agentdeck-${process.env.GITHUB_RUN_ID ?? Date.now()}`;
const modelId = process.env.R2_RELAY_E2E_MODEL ?? "deepseek/deepseek-v4-flash";
const textCheckToken = process.env.R2_RELAY_E2E_TEXT_TOKEN ?? "TEXT-CHECK-7391";
const imageCheckToken = process.env.R2_RELAY_E2E_IMAGE_TOKEN ?? "IMAGE-CHECK-RED";
const fileCheckToken = process.env.R2_RELAY_E2E_FILE_TOKEN ?? "FILE-CHECK-5821";
const fileAttachmentCaption = process.env.R2_RELAY_E2E_FILE_CAPTION ?? "FILE-CHECK-ATTACHMENT";
const fileAttachmentName = process.env.R2_RELAY_E2E_FILE_NAME ?? "relay-file-check.txt";
const webhookToken = process.env.R2_RELAY_E2E_WEBHOOK_TOKEN ?? "relay-e2e-webhook-token";
const serverResponseAttachmentToken =
  process.env.R2_RELAY_E2E_SERVER_ATTACHMENT_TOKEN ?? "SERVER-ATTACHMENT-RESPONSE-6124";
const serverResponseAttachmentCaption =
  process.env.R2_RELAY_E2E_SERVER_ATTACHMENT_CAPTION ?? "SERVER-ATTACHMENT-RESPONSE-FILE";
const webhookFileAttachmentCaption = process.env.R2_RELAY_E2E_WEBHOOK_FILE_CAPTION ?? "WEBHOOK-FILE-CHECK-ATTACHMENT";
const home = process.env.R2_RELAY_E2E_HOME ?? fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-e2e-home-"));
const artifactsDir = process.env.R2_RELAY_E2E_ARTIFACTS_DIR ?? path.join(pluginRoot, "e2e-artifacts");
const gatewayLogPath = path.join(artifactsDir, "openclaw-gateway.log");

fs.mkdirSync(artifactsDir, { recursive: true });
fs.mkdirSync(path.join(home, ".openclaw"), { recursive: true });

const childEnv = {
  ...process.env,
  HOME: home,
  OPENCLAW_HOME: path.join(home, ".openclaw"),
  DEEPSEEK_API_KEY: process.env.DEEPSEEK_API_KEY ?? "",
  NO_COLOR: "1",
  CI: "1",
};

function redact(value) {
  return value
    .replaceAll(process.env.DEEPSEEK_API_KEY ?? "___missing___", "<redacted:DEEPSEEK_API_KEY>")
    .replaceAll(webhookToken, "<redacted:R2_WEBHOOK_TOKEN>")
    .replaceAll(secretAccessKey, "<redacted:R2_SECRET_ACCESS_KEY>");
}

function writeArtifact(name, contents) {
  fs.writeFileSync(path.join(artifactsDir, name), redact(String(contents)), "utf8");
}

async function run(command, args, options = {}) {
  const label = `${command} ${args.join(" ")}`;
  console.log(`$ ${redact(label)}`);
  return await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd ?? pluginRoot,
      env: options.env ?? childEnv,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
      if (!options.quiet) process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      if (!options.quiet) process.stderr.write(chunk);
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0 || options.allowFailure) {
        resolve({ code, stdout, stderr });
        return;
      }
      reject(new Error(redact(`${label} failed with exit code ${code}\n${stdout}\n${stderr}`)));
    });
  });
}

async function runOpenClaw(args, options = {}) {
  return await run("openclaw", args, options);
}

async function configureDeepSeek() {
  if (!process.env.DEEPSEEK_API_KEY) {
    throw new Error("DEEPSEEK_API_KEY is required for the OpenClaw relay E2E.");
  }
  await runOpenClaw([
    "onboard",
    "--non-interactive",
    "--mode",
    "local",
    "--auth-choice",
    "deepseek-api-key",
    "--deepseek-api-key",
    process.env.DEEPSEEK_API_KEY,
    "--skip-health",
    "--accept-risk",
  ]);
  await runOpenClaw(["models", "list", "--all", "--provider", "deepseek"], { quiet: true });
  await runOpenClaw(["models", "set", modelId], { allowFailure: true });
}

async function installPlugin() {
  const installFlags = ["--force", "--dangerously-force-unsafe-install"];
  const installSpec = process.env.R2_RELAY_E2E_PLUGIN_SPEC;
  if (installSpec) {
    await runOpenClaw(["plugins", "install", installSpec, ...installFlags]);
    return;
  }

  const localSpec = process.env.R2_RELAY_E2E_LOCAL_PLUGIN_SPEC ?? pluginRoot;
  await runOpenClaw(["plugins", "install", stageLocalPluginForInstall(localSpec), ...installFlags]);
}

function stageLocalPluginForInstall(localSpec) {
  const source = path.resolve(localSpec);
  const packagePath = path.join(source, "package.json");
  if (!fs.existsSync(packagePath)) {
    return localSpec;
  }

  const stagedRoot = fs.mkdtempSync(path.join(os.tmpdir(), "r2-relay-channel-plugin-"));
  const excluded = new Set([".git", "e2e-artifacts"]);
  fs.cpSync(source, stagedRoot, {
    recursive: true,
    dereference: true,
    filter: (src) => {
      const name = path.basename(src);
      if (excluded.has(name)) return false;
      if (name.endsWith(".tgz")) return false;
      return true;
    },
  });

  const stagedPackagePath = path.join(stagedRoot, "package.json");
  const stagedPackage = JSON.parse(fs.readFileSync(stagedPackagePath, "utf8"));
  const hostOpenClawVersion = resolveInstalledOpenClawVersion();
  if (stagedPackage.dependencies?.openclaw && hostOpenClawVersion) {
    stagedPackage.dependencies.openclaw = hostOpenClawVersion;
  }
  fs.writeFileSync(stagedPackagePath, `${JSON.stringify(stagedPackage, null, 2)}\n`, "utf8");
  for (const lockName of ["package-lock.json", "npm-shrinkwrap.json"]) {
    const lockPath = path.join(stagedRoot, lockName);
    if (fs.existsSync(lockPath)) {
      fs.rmSync(lockPath);
    }
  }

  writeArtifact("local-plugin-install-path.txt", stagedRoot);
  return stagedRoot;
}

function resolveInstalledOpenClawVersion() {
  try {
    const output = execFileSync("openclaw", ["--version"], {
      encoding: "utf8",
      env: childEnv,
    });
    return output.match(/OpenClaw\s+([^\s]+)/)?.[1] ?? null;
  } catch {
    return null;
  }
}

async function configureRelayChannel() {
  const sidecarPath = path.join(home, ".openclaw", "r2relay.config.json");
  await runOpenClaw([
    "config",
    "set",
    "plugins.allow",
    JSON.stringify(["r2-relay-channel"]),
    "--strict-json",
  ]);
  await runOpenClaw([
    "config",
    "set",
    "update.checkOnStart",
    "false",
    "--strict-json",
  ]);
  await runOpenClaw([
    "config",
    "set",
    "plugins.entries.r2-relay-channel",
    JSON.stringify({ enabled: true }),
    "--strict-json",
    "--merge",
  ]);
  await runOpenClaw([
    "config",
    "set",
    "channels.r2-relay-channel",
    JSON.stringify({ enabled: true, configFile: sidecarPath }),
    "--strict-json",
  ]);
  await runOpenClaw([
    "config",
    "set",
    "cron.webhookToken",
    JSON.stringify(webhookToken),
    "--strict-json",
  ]);
  const sidecar = {
    enabled: true,
    endpoint,
    bucket,
    accessKeyId,
    secretAccessKey,
    serverId,
    pollIntervalMs: 500,
    backoffMaxMs: 2000,
    defaultTtlDays: 1,
    ttl: {
      msg: 1,
      att: 1,
      identity: 1,
      head: 1,
    },
  };
  fs.writeFileSync(sidecarPath, `${JSON.stringify(sidecar, null, 2)}\n`, "utf8");
  writeArtifact("r2relay.config.redacted.json", JSON.stringify(sidecar, null, 2));
  await runOpenClaw(["config", "validate"]);

  const inspect = await runOpenClaw(["plugins", "inspect", "r2-relay-channel", "--json"], { quiet: true });
  writeArtifact("plugin-inspect.json", inspect.stdout);
}

function resolveOpenClawWorkspaceDir() {
  const configPath = path.join(childEnv.OPENCLAW_HOME, "openclaw.json");
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const workspace = cfg?.agents?.defaults?.workspace;
    if (typeof workspace === "string" && workspace.trim()) {
      return path.resolve(expandOpenClawConfigPath(workspace.trim()));
    }
  } catch {
    // Fall through to the onboarding default.
  }
  return path.join(childEnv.OPENCLAW_HOME, ".openclaw", "workspace");
}

function expandOpenClawConfigPath(value) {
  return value
    .replaceAll("$OPENCLAW_HOME", childEnv.OPENCLAW_HOME)
    .replaceAll("${OPENCLAW_HOME}", childEnv.OPENCLAW_HOME)
    .replaceAll("$HOME", childEnv.HOME)
    .replaceAll("${HOME}", childEnv.HOME);
}

function stageFileAttachmentFixture() {
  const workspaceDir = resolveOpenClawWorkspaceDir();
  fs.mkdirSync(workspaceDir, { recursive: true });
  const fixturePath = path.join(workspaceDir, fileAttachmentName);
  fs.writeFileSync(fixturePath, `${fileCheckToken}\n`, "utf8");
  writeArtifact("file-check-fixture.json", JSON.stringify({
    workspaceDir,
    path: fixturePath,
    fileName: fileAttachmentName,
    expected: fileCheckToken,
  }, null, 2));
  return { workspaceDir, fixturePath };
}

async function sendFileAttachmentViaOpenClaw(fixturePath) {
  const target = `peer=${clientPeer},conversation=agent:main:main`;
  const baseArgs = [
    "message",
    "send",
    "--channel",
    "r2-relay-channel",
    "--target",
    target,
    "--message",
    fileAttachmentCaption,
  ];
  const attempts = [];
  for (const mediaFlag of ["--media", "--file", "--attachment"]) {
    const args = [...baseArgs, mediaFlag, fixturePath];
    attempts.push(`openclaw ${args.join(" ")}`);
    const result = await runOpenClaw(args, { allowFailure: true });
    if (result.code === 0) {
      writeArtifact("file-send-command.txt", `${attempts.join("\n")}\n`);
      return;
    }
    attempts.push(`exit=${result.code}\n${result.stdout}${result.stderr}`);
  }
  writeArtifact("file-send-command.txt", `${attempts.join("\n")}\n`);
  throw new Error("openclaw message send did not accept any supported file attachment flag.");
}

function resolveGatewayBaseUrl() {
  const configPath = path.join(childEnv.OPENCLAW_HOME, "openclaw.json");
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const port = cfg?.gateway?.port;
    if (typeof port === "number" && Number.isFinite(port) && port > 0) {
      return `http://127.0.0.1:${port}`;
    }
  } catch {
    // Fall through to the default local gateway port.
  }
  return "http://127.0.0.1:18789";
}

async function sendWebhookAttachmentReply(fixturePath, options = {}) {
  const url = `${resolveGatewayBaseUrl()}/r2-relay-channel/webhook/${encodeURIComponent(clientPeer)}/${encodeURIComponent("agent:main:main")}`;
  const payload = {
    text: options.text ?? webhookFileAttachmentCaption,
    mediaUrl: fixturePath,
    jobId: options.jobId ?? "e2e-webhook-file-attachment",
    status: options.status ?? "ok",
  };
  writeArtifact(options.requestArtifactName ?? "webhook-file-request.json", JSON.stringify({ url, payload }, null, 2));
  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${webhookToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const raw = await response.text();
  writeArtifact(options.responseArtifactName ?? "webhook-file-response.json", JSON.stringify({
    status: response.status,
    ok: response.ok,
    body: raw,
  }, null, 2));
  assert.ok(response.ok, `webhook attachment delivery failed with status ${response.status}: ${raw}`);
}

function startGateway() {
  const log = fs.createWriteStream(gatewayLogPath, { flags: "a" });
  const child = spawn("openclaw", ["gateway", "run"], {
    cwd: pluginRoot,
    env: childEnv,
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => {
    process.stdout.write(chunk);
    log.write(redact(chunk.toString()));
  });
  child.stderr.on("data", (chunk) => {
    process.stderr.write(chunk);
    log.write(redact(chunk.toString()));
  });
  child.on("exit", (code, signal) => {
    log.write(`\n[gateway exited code=${code} signal=${signal}]\n`);
    log.end();
  });
  return child;
}

function assertGatewayLogClean() {
  if (!fs.existsSync(gatewayLogPath)) return;
  const log = fs.readFileSync(gatewayLogPath, "utf8");
  const readFailures = log.split(/\r?\n/).filter((line) => line.includes("[tools] read failed"));
  assert.deepEqual(readFailures, [], `OpenClaw tool read failures were logged:\n${readFailures.join("\n")}`);
}

async function stopGateway(child) {
  if (!child || child.exitCode !== null) return;
  child.kill("SIGTERM");
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (child.exitCode === null) child.kill("SIGKILL");
      resolve();
    }, 5000);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function assertServerIdentity(identity) {
  assert.equal(identity.peer, serverId);
  assert.equal(identity.role, "server");
  assert.equal(identity.protocol?.name, "r2-relay");
  assert.equal(identity.protocol?.version, 3);
  assert.equal(identity.software?.id, "openclaw");
  assert.equal(identity.capabilities?.messaging?.text, true);
}

function assertAssistantReply(entry, expectedPattern) {
  assert.equal(entry.message.from, serverId);
  assert.equal(entry.message.to, clientPeer);
  assert.equal(entry.message.route.conversation_id, "agent:main:main");
  assert.equal(entry.message.content.type, "text");
  assert.match(entry.message.content.text ?? "", expectedPattern);
}

function assertServerRelayMessage(entry, expectedPattern) {
  assert.equal(entry.message.from, serverId);
  assert.equal(entry.message.to, clientPeer);
  assert.equal(entry.message.content.type, "text");
  assert.match(entry.message.content.text ?? "", expectedPattern);
}

async function collectNewAssistantReply(client, sinceHeadKey, expectedPattern, description) {
  return await waitFor(description, async () => {
    const chain = await client.collectChain(clientPeer, sinceHeadKey);
    return chain.messages.find((entry) =>
      entry.message.from === serverId &&
      entry.message.content?.type === "text" &&
      expectedPattern.test(entry.message.content.text ?? "")
    ) ?? null;
  }, { timeoutMs: 180_000, intervalMs: 1000 });
}

async function collectNewAssistantReplyWithBody(client, sinceHeadKey, description, options = {}) {
  return await waitFor(description, async () => {
    const chain = await client.collectChain(clientPeer, sinceHeadKey);
    return chain.messages.find((entry) =>
      entry.message.from === serverId &&
      entry.message.content?.type === "text" &&
      typeof entry.message.content.text === "string" &&
      entry.message.content.text.trim().length > 0
    ) ?? null;
  }, { timeoutMs: options.timeoutMs ?? 240_000, intervalMs: 1000 });
}

async function collectNewAssistantAttachmentReply(client, sinceHeadKey, expectedPattern, description) {
  return await waitFor(description, async () => {
    const chain = await client.collectChain(clientPeer, sinceHeadKey);
    return chain.messages.find((entry) =>
      entry.message.from === serverId &&
      entry.message.content?.type === "text" &&
      Array.isArray(entry.message.content.attachments) &&
      entry.message.content.attachments.length > 0 &&
      expectedPattern.test(entry.message.content.text ?? "")
    ) ?? null;
  }, { timeoutMs: 240_000, intervalMs: 1000 });
}

async function waitForProcessed(client, key, description) {
  return await waitFor(description, async () => {
    const message = await client.tryGetJson(key);
    return ["done", "error"].includes(message?.status?.state) ? message : null;
  }, { timeoutMs: 180_000, intervalMs: 1000 });
}

async function waitForProcessedConfirmation(client, sinceHeadKey, inboundMessageId) {
  return await waitFor(`processed confirmation for ${inboundMessageId}`, async () => {
    const chain = await client.collectChain(clientPeer, sinceHeadKey);
    return chain.messages.find((entry) =>
      entry.message.from === serverId &&
      entry.message.content?.type === "reaction" &&
      entry.message.content.target_msg_id === inboundMessageId &&
      entry.message.content.emoji === "✅"
    ) ?? null;
  }, { timeoutMs: 180_000, intervalMs: 1000 });
}

function createSolidPng(width, height, rgba) {
  const rowStride = width * 4 + 1;
  const raw = Buffer.alloc(rowStride * height);
  for (let y = 0; y < height; y += 1) {
    const rowOffset = y * rowStride;
    raw[rowOffset] = 0;
    for (let x = 0; x < width; x += 1) {
      const offset = rowOffset + 1 + x * 4;
      raw[offset] = rgba[0];
      raw[offset + 1] = rgba[1];
      raw[offset + 2] = rgba[2];
      raw[offset + 3] = rgba[3];
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", Buffer.concat([
      uint32be(width),
      uint32be(height),
      Buffer.from([8, 6, 0, 0, 0]),
    ])),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const crcInput = Buffer.concat([typeBytes, data]);
  return Buffer.concat([
    uint32be(data.length),
    typeBytes,
    data,
    uint32be(crc32(crcInput)),
  ]);
}

function uint32be(value) {
  const buf = Buffer.alloc(4);
  buf.writeUInt32BE(value >>> 0);
  return buf;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

async function main() {
  console.log(`Using OpenClaw home: ${home}`);
  console.log(`Using relay bucket: ${bucket}`);

  const client = new RelayTestClient({ endpoint, bucket, accessKeyId, secretAccessKey });
  await client.ensureBucket();
  await client.deletePrefix("");

  await runOpenClaw(["--version"], { quiet: true }).then((res) => writeArtifact("openclaw-version.txt", res.stdout));
  await configureDeepSeek();
  await installPlugin();
  await configureRelayChannel();
  const fileFixture = stageFileAttachmentFixture();

  const gateway = startGateway();
  try {
    const identity = await waitFor(`server identity ${serverId}`, async () => {
      return await client.tryGetJson(client.makeIdentityKey(serverId));
    }, { timeoutMs: 120_000, intervalMs: 1000 });
    assertServerIdentity(identity);
    writeArtifact("server-identity.json", JSON.stringify(identity, null, 2));

    await client.publishClientIdentity(clientPeer);
    const route = {
      agent_id: "main",
      conversation_id: "agent:main:main",
    };

    const beforeTextHead = (await client.collectChain(clientPeer)).head?.head_key ?? null;
    const inbound = await client.appendMessage({
      from: clientPeer,
      to: serverId,
      body: `This is a text-only relay conversation check. Reply with exactly ${textCheckToken} and nothing else. Do not use tools.`,
      route,
    });

    await waitForProcessed(client, inbound.key, `processed marker for ${inbound.key}`);

    const processedConfirmation = await waitForProcessedConfirmation(client, beforeTextHead, inbound.messageId);
    assert.equal(processedConfirmation.message.content.remove, false);

    const reply = await collectNewAssistantReply(
      client,
      beforeTextHead,
      new RegExp(textCheckToken.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
      `DeepSeek-backed text reply to ${clientPeer}`,
    );
    assertAssistantReply(reply, new RegExp(textCheckToken.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));

    const beforeImageHead = (await client.collectChain(clientPeer)).head?.head_key ?? null;
    const redPng = createSolidPng(64, 64, [230, 0, 0, 255]);
    const imageMessage = await client.appendAttachmentMessage({
      from: clientPeer,
      to: serverId,
      body: `Look at the attached image and reply with one short sentence starting with IMAGE-CHECK that names the dominant color if visible. Do not use tools.`,
      route,
      fileName: "visual-check.png",
      contentType: "image/png",
      data: redPng,
      kind: "image",
      width: 64,
      height: 64,
    });
    writeArtifact("image-check-metadata.json", JSON.stringify({
      key: imageMessage.message.content.attachments?.[0]?.key ?? null,
      contentType: "image/png",
      width: 64,
      height: 64,
      expected: imageCheckToken,
    }, null, 2));
    await waitForProcessed(client, imageMessage.key, `processed marker for image message ${imageMessage.key}`);
    const imageReply = await collectNewAssistantReplyWithBody(
      client,
      beforeImageHead,
      `DeepSeek-backed image reply to ${clientPeer}`,
    );
    assertAssistantReply(imageReply, /.+/);
    assert.match(
      imageReply.message.content.text ?? "",
      /IMAGE-CHECK|red|image/i,
      "image reply should acknowledge the image turn",
    );

    const reaction = await client.appendReaction({
      from: clientPeer,
      to: serverId,
      targetMessageId: imageReply.message.msg_id,
      emoji: "👍",
      route,
    });
    await waitForProcessed(client, reaction.key, `processed marker for reaction ${reaction.key}`);

    const beforeServerAttachmentReplyHead = (await client.collectChain(clientPeer)).head?.head_key ?? null;
    const serverAttachmentRequest = await client.appendMessage({
      from: clientPeer,
      to: serverId,
      body: [
        "This is the dedicated server attachment response relay check.",
        `Expect one attachment reply whose caption contains ${serverResponseAttachmentToken}.`,
      ].join(" "),
      route,
    });
    await waitForProcessed(
      client,
      serverAttachmentRequest.key,
      `processed marker for server attachment request ${serverAttachmentRequest.key}`,
    );
    await sendWebhookAttachmentReply(fileFixture.fixturePath, {
      text: `${serverResponseAttachmentCaption} ${serverResponseAttachmentToken}`,
      jobId: "e2e-server-attachment-response",
      requestArtifactName: "server-attachment-response-request.json",
      responseArtifactName: "server-attachment-response.json",
    });
    const serverAttachmentReply = await collectNewAssistantAttachmentReply(
      client,
      beforeServerAttachmentReplyHead,
      new RegExp(serverResponseAttachmentToken.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
      `server attachment reply to ${clientPeer}`,
    );
    assertServerRelayMessage(
      serverAttachmentReply,
      new RegExp(serverResponseAttachmentToken.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
    );
    const serverResponseAttachment = serverAttachmentReply.message.content.attachments?.[0];
    assert.ok(serverResponseAttachment?.key, "server attachment response should include an attachment key");
    assert.equal(serverResponseAttachment.kind, "file");
    assert.equal(serverResponseAttachment.file_name, fileAttachmentName);
    const serverResponseAttachmentBuffer = await client.getObjectBuffer(serverResponseAttachment.key);
    assert.equal(serverResponseAttachmentBuffer.toString("utf8"), `${fileCheckToken}\n`);
    writeArtifact("server-attachment-response-metadata.json", JSON.stringify({
      requestMessageId: serverAttachmentRequest.messageId,
      replyMessageId: serverAttachmentReply.message.msg_id,
      key: serverResponseAttachment.key,
      fileName: serverResponseAttachment.file_name ?? null,
      contentType: serverResponseAttachment.content_type ?? null,
      size: serverResponseAttachment.size ?? null,
      expected: fileCheckToken,
    }, null, 2));

    const beforeFileHead = (await client.collectChain(clientPeer)).head?.head_key ?? null;
    const fileRequest = await client.appendMessage({
      from: clientPeer,
      to: serverId,
      body: [
        `Please send me the existing local workspace file ${fileAttachmentName} as an attachment.`,
        `This is the file attachment relay check for token ${fileCheckToken}.`,
      ].join(" "),
      route,
    });
    await waitForProcessed(client, fileRequest.key, `processed marker for file request ${fileRequest.key}`);
    await sendFileAttachmentViaOpenClaw(fileFixture.fixturePath);
    const fileReply = await collectNewAssistantAttachmentReply(
      client,
      beforeFileHead,
      new RegExp(fileAttachmentCaption.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
      `file attachment reply to ${clientPeer}`,
    );
    assertServerRelayMessage(fileReply, new RegExp(fileAttachmentCaption.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    const fileAttachment = fileReply.message.content.attachments?.[0];
    assert.ok(fileAttachment?.key, "file reply should include an attachment key");
    assert.equal(fileAttachment.kind, "file");
    assert.equal(fileAttachment.file_name, fileAttachmentName);
    const fileAttachmentBuffer = await client.getObjectBuffer(fileAttachment.key);
    const fileAttachmentText = fileAttachmentBuffer.toString("utf8");
    assert.equal(fileAttachmentText, `${fileCheckToken}\n`);
    writeArtifact("file-check-metadata.json", JSON.stringify({
      key: fileAttachment.key,
      fileName: fileAttachment.file_name ?? null,
      contentType: fileAttachment.content_type ?? null,
      size: fileAttachment.size ?? null,
      expected: fileCheckToken,
    }, null, 2));

    const beforeWebhookFileHead = (await client.collectChain(clientPeer)).head?.head_key ?? null;
    const webhookFileRequest = await client.appendMessage({
      from: clientPeer,
      to: serverId,
      body: [
        `Please send me the same local workspace file ${fileAttachmentName} back as an attachment.`,
        `Use the webhook/session delivery path for this reply.`,
      ].join(" "),
      route,
    });
    await waitForProcessed(client, webhookFileRequest.key, `processed marker for webhook file request ${webhookFileRequest.key}`);
    await sendWebhookAttachmentReply(fileFixture.fixturePath);
    const webhookFileReply = await collectNewAssistantAttachmentReply(
      client,
      beforeWebhookFileHead,
      new RegExp(webhookFileAttachmentCaption.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
      `webhook file attachment reply to ${clientPeer}`,
    );
    assertServerRelayMessage(webhookFileReply, new RegExp(webhookFileAttachmentCaption.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    const webhookFileAttachment = webhookFileReply.message.content.attachments?.[0];
    assert.ok(webhookFileAttachment?.key, "webhook file reply should include an attachment key");
    assert.equal(webhookFileAttachment.kind, "file");
    assert.equal(webhookFileAttachment.file_name, fileAttachmentName);
    const webhookFileBuffer = await client.getObjectBuffer(webhookFileAttachment.key);
    assert.equal(webhookFileBuffer.toString("utf8"), `${fileCheckToken}\n`);
    writeArtifact("webhook-file-check-metadata.json", JSON.stringify({
      key: webhookFileAttachment.key,
      fileName: webhookFileAttachment.file_name ?? null,
      contentType: webhookFileAttachment.content_type ?? null,
      size: webhookFileAttachment.size ?? null,
      expected: fileCheckToken,
    }, null, 2));

    const objectDump = await client.dumpObjects();
    writeArtifact("relay-objects.json", JSON.stringify(objectDump, null, 2));

    const clientChain = await client.collectChain(clientPeer);
    assert.ok(clientChain.messages.length >= 1, "client inbox should contain at least one server message");
    assert.ok(clientChain.head?.head_key, "client head should be present");
    await stopGateway(gateway);
    assertGatewayLogClean();
    console.log("r2-relay-channel OpenClaw E2E passed.");
  } catch (err) {
    try {
      writeArtifact("relay-objects.failure.json", JSON.stringify(await client.dumpObjects(), null, 2));
    } catch (dumpErr) {
      writeArtifact("relay-objects.failure.txt", dumpErr instanceof Error ? dumpErr.stack ?? dumpErr.message : String(dumpErr));
    }
    throw err;
  } finally {
    await stopGateway(gateway);
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack ?? err.message : String(err));
  process.exitCode = 1;
});
