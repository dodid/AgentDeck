# Test AgentDeck on an iPhone

AgentDeck communicates through Cloudflare R2. The iPhone does not connect directly to the OpenClaw or Hermes host, so the staging server needs no inbound application ports.

## 1. Prepare Cloudflare R2

Create one R2 bucket and an API token that can read and write objects in that bucket. Record:

- the S3 endpoint, such as `https://ACCOUNT_ID.r2.cloudflarestorage.com`;
- the bucket name;
- the access key ID;
- the secret access key.

Use dedicated staging credentials. Do not use a Cloudflare account-wide token.

## 2. Prepare the Ubuntu host

The installer creates isolated user-level services named `openclaw-gateway-agentdeck` and `hermes-gateway-agentdeck`. It does not stop, replace, or reconfigure other services.

On the server:

```sh
git clone https://github.com/dodid/AgentDeck.git
cd AgentDeck
mkdir -p ~/.config/agentdeck
cp tools/staging/staging.env.example ~/.config/agentdeck/staging.env
chmod 600 ~/.config/agentdeck/staging.env
editor ~/.config/agentdeck/staging.env
```

Set `OPENROUTER_API_KEY` and the four `R2_RELAY_*` values. `AGENTDECK_MODEL` defaults to OpenRouter's automatic router; replace it with a specific OpenRouter model slug if preferred.

Install and start both platforms:

```sh
tools/staging/setup-ubuntu.sh install
tools/staging/setup-ubuntu.sh verify
```

Useful operations:

```sh
tools/staging/setup-ubuntu.sh status
tools/staging/setup-ubuntu.sh logs
tools/staging/setup-ubuntu.sh restart
tools/staging/setup-ubuntu.sh stop
```

The installer uses the OpenClaw version and Hermes commit recorded in `compatibility.json`. Re-running it after updating the AgentDeck checkout updates the isolated staging installations to the repository's tested versions.

## 3. Install the iOS app

For a development build:

1. Connect the iPhone to the Mac and enable Developer Mode on the phone.
2. Open `apps/ios/AgentDeck.xcodeproj` in Xcode.
3. Select the `AgentDeck` target and your Apple development team under **Signing & Capabilities**.
4. Select the connected iPhone as the run destination.
5. Click **Run**.

The project retains the existing App Store bundle identifier. The selected Apple team must own or be authorized to sign that identifier. TestFlight is the alternative when a signed build is available there.

## 4. Connect AgentDeck

In AgentDeck, enter the same R2 endpoint, bucket, access key ID, and secret access key used by the server. After verification, the gateway list should show separate OpenClaw and Hermes entries.

Test each gateway independently:

1. open a conversation;
2. send a short message;
3. confirm streamed text reaches the phone;
4. send an image or file in both directions;
5. background and reopen the app to confirm synchronization resumes.

If discovery fails, run `tools/staging/setup-ubuntu.sh verify` and then inspect `tools/staging/setup-ubuntu.sh logs` on the server.
