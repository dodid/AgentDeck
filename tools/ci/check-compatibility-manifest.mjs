import fs from "node:fs";

const compatibility = JSON.parse(fs.readFileSync("compatibility.json", "utf8"));
const openclawPackage = JSON.parse(fs.readFileSync("integrations/openclaw/package.json", "utf8"));
const schema = JSON.parse(fs.readFileSync("packages/relay-core/spec/relay-contract-v3.schema.json", "utf8"));

const declaredOpenClaw = openclawPackage.dependencies.openclaw.replace(/^[^0-9]*/, "");
if (declaredOpenClaw !== compatibility.openclaw.tested_version) {
  throw new Error(`compatibility.json OpenClaw ${compatibility.openclaw.tested_version} does not match package.json ${declaredOpenClaw}`);
}

const protocolVersion = schema.$defs.protocol.properties.version.const;
if (protocolVersion !== compatibility.protocol) {
  throw new Error(`compatibility.json protocol ${compatibility.protocol} does not match schema ${protocolVersion}`);
}

if (!/^[0-9a-f]{40}$/.test(compatibility.hermes.tested_commit)) {
  throw new Error("compatibility.json must pin Hermes to a full commit hash");
}

console.log("Compatibility manifest matches the committed contract and OpenClaw dependency.");
