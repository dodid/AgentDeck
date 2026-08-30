# Attachment Implementation Plan

_Status: in progress._

_Last updated: 2026-04-11 05:45 EDT._

This checklist tracks the staged implementation of first-class attachment support for:

- `r2-relay-channel/`
- `ClawChat/`

## Stage 1 — Shared protocol foundation ✅

- [x] Define canonical `AttachmentRef` in `r2-relay-channel/src/protocol.ts`
- [x] Mirror attachment model in `ClawChat/ClawChat/Services/Relay/RelayMessageModels.swift`
- [x] Remove old special attachment-message-type assumption
- [x] Accept attachment-only messages in iOS inbox ingest
- [x] Write implementation design doc

## Stage 2 — Plugin transport and relay delivery ✅

- [x] Advertise attachment/media support from the plugin (`media: true`, identity capability)
- [x] Add plugin-side `sendPayload` handler for outbound attachments (mediaUrl/mediaUrls → R2 upload → relay message)
- [x] Implement payload-aware outbound delivery for text + attachments in one relay message
- [x] Keep CAS retries message-only, reusing uploaded attachment objects (by design: uploads before CAS loop)
- [x] Add inbound attachment manifest/context plumbing for agent dispatch
- [x] Add inbound media understanding integration (image-to-text for agent context)

## Stage 3 — iOS domain and persistence

- [x] Add first-class attachment domain types
- [x] Add attachment persistence table(s)
- [x] Hydrate transcript messages with attachments
- [x] Preserve attachment metadata for incoming messages
- [x] Preserve local draft attachment metadata for outgoing messages prior to upload
- [x] Reconcile local draft attachments with uploaded relay attachment metadata after send

## Stage 4 — iOS send flow

- [x] Widen repository/sync APIs to send text + attachments
- [x] Add local draft attachment/message creation
- [x] Upload local draft attachments before relay message commit (basic original-file upload only)
- [x] Reuse uploaded attachments across CAS retries (verified: uploads happen before CAS loop)
- [x] Reconcile pending local draft attachments into canonical uploaded relay attachment refs before send
- [x] Add preview/poster generation and richer metadata extraction for uploaded attachments

## Stage 5 — iOS chat UX

- [x] Add composer attachment picker/tray
- [x] Render basic attachment cards/list rows in transcript
- [x] Upgrade transcript rendering to image/video grids and richer media previews
- [x] Support basic downloading/export of received attachments (lazy download manager + share/export on tap)
- [x] Show basic local send/pending/uploaded failure states in transcript metadata
- [x] Add basic full-screen image viewer / tapped video-audio playback / richer non-image export flow

## Stage 6 — Verification and docs

- [x] Run plugin build/checks (TypeScript clean, npm build passes)
- [x] Perform iOS compile-level verification (BUILD SUCCEEDED via mac bridge)
- [x] Update architecture/workflow docs
- [x] Summarize remaining gaps/follow-ups

## Remaining follow-ups

1. Plugin inbound media understanding
   - use OpenClaw media-understanding runtime so supported inbound images can be passed as real media inputs to the agent, not just manifest text
   - keep manifest text as fallback for unsupported media types

2. iOS attachment UX polish
   - richer zoom/pan behavior and gallery-style navigation for images
   - inline video presentation polish and better audio-specific controls
   - richer file open flows beyond export/share when native previews are available

3. Attachment transport hardening
   - stricter content-type inference
   - explicit size limits and clearer user-facing errors for oversized media
   - optional upload dedupe / resumable improvements if v2 needs them
