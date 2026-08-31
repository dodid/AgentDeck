#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const [openclawVersion, hermesCommit] = process.argv.slice(2);
if (!openclawVersion || !/^\d+\.\d+\.\d+/.test(openclawVersion)) {
  throw new Error("usage: update-compatibility.mjs <openclaw-version> <hermes-commit>");
}
if (!hermesCommit || !/^[0-9a-f]{40}$/.test(hermesCommit)) {
  throw new Error("Hermes commit must be a full 40-character SHA");
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const compatibilityPath = path.join(root, "compatibility.json");
const packagePath = path.join(root, "integrations/openclaw/package.json");
const compatibility = JSON.parse(fs.readFileSync(compatibilityPath, "utf8"));
const packageJSON = JSON.parse(fs.readFileSync(packagePath, "utf8"));

compatibility.openclaw.tested_version = openclawVersion;
compatibility.hermes.tested_commit = hermesCommit;
packageJSON.dependencies.openclaw = `^${openclawVersion}`;
packageJSON.openclaw.build.openclawVersion = openclawVersion;
packageJSON.openclaw.build.pluginSdkVersion = openclawVersion;

fs.writeFileSync(compatibilityPath, `${JSON.stringify(compatibility, null, 2)}\n`);
fs.writeFileSync(packagePath, `${JSON.stringify(packageJSON, null, 2)}\n`);
