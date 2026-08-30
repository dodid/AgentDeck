# Attachment Relay Design (Archived)

> Historical pre-v3 design notes. Current attachment fields are defined by `r2-relay-core/spec/relay-contract-v3.schema.json` and the platform implementations.

_Status: planned design, not yet implemented._

_Last updated: 2026-04-09._

This document captures the intended end-to-end design for first-class attachment support across:

- `r2-relay-channel/` — the OpenClaw relay plugin
- `ClawChat/` — the iOS client

It is a forward-looking implementation design, not a statement of current behavior. For current implemented architecture, see `ARCHITECTURE_TRUTH.md`.

---

## Goals

Provide attachment support that feels like a normal modern chat product:

- send text with zero or more attachments in one message
- send attachment-only messages
- receive and render attachments naturally in the transcript
- allow assistant replies to include one or more attachments as a single message bundle
- use the shared R2 bucket for storage and relay
- keep the relay message chain simple and robust
- avoid unnecessary retransmission on message CAS retries
- avoid huge-file complexity in the initial implementation

---

## Explicit design decisions

### 1. No backward compatibility for `AttachmentRef`

We will define one canonical attachment descriptor and update both the plugin and the iOS app together.

We do **not** need to preserve compatibility with the current minimal shape:

```ts
{ key: string; size?: number; content_type?: string }
```

The new descriptor becomes the only supported attachment wire format for this feature rollout.

### 2. CAS commit retries must not re-upload attachments

Attachment uploads and message commit are separate phases.

Flow:

1. upload all attachment objects to R2
2. build stable `AttachmentRef[]`
3. attempt message append + head CAS update
4. if CAS fails, regenerate only the message object key / message document and retry
5. reuse the already-uploaded attachment objects and the same `AttachmentRef[]`

This keeps retries cheap and avoids duplicate object writes.

### 3. Huge files are out of scope for v1

Initial implementation should support common chat attachment sizes and types cleanly.

We do **not** need in v1:

- multipart upload
- resumable uploads
- streaming download UX for very large assets
- special handling for giant videos or archives

We can introduce explicit size limits in the implementation for now, even if the long-term transport model remains flexible.

### 4. Attachments are part of normal messages, not a separate message class

A relay message may contain:

- `body` only
- `attachments` only
- `body` + `attachments`

The presence of attachments does not require a special message type.

### 5. Assistant multi-attachment replies should arrive as one message bundle

For `r2-relay-channel`, assistant replies with multiple attachments should be delivered as a single relay message with a single `attachments[]` array, not split across many relay messages.

This implies channel/plugin support for payload-level delivery rather than only text-only or one-media-at-a-time delivery.

---

## Wire contract

## Canonical relay message behavior

A normal chat message is valid when either of the following is true:

- `body` is non-empty after trimming
- `attachments.length > 0`

Relay message `type` remains reserved for semantic cases such as:

- `reaction`
- `assistant_stream`

Normal messages with attachments should still use the normal message path.

## Canonical `AttachmentRef`

```ts
export interface AttachmentRef {
  id: string;
  key: string;
  file_name: string | null;
  content_type: string | null;
  size: number | null;
  sha256: string | null;

  kind: "image" | "video" | "audio" | "file" | "unknown";

  width: number | null;
  height: number | null;
  duration_ms: number | null;

  preview_image_key: string | null;
  preview_image_type: string | null;
  preview_size: number | null;
}
```

## Field notes

- `id`: stable per-message attachment identifier (`"a1"`, `"a2"`, ...)
- `key`: R2 object key for the original object
- `file_name`: original filename when known
- `content_type`: MIME type
- `size`: original object size in bytes
- `sha256`: optional integrity field
- `kind`: rendering hint for transcript/UI behavior
- `width` / `height`: image and video rendering metadata
- `duration_ms`: audio/video duration when available
- `preview_image_key`: optional R2 key for thumbnail/poster
- `preview_image_type`: preview MIME type, typically image/jpeg or image/png
- `preview_size`: preview object size in bytes

## Relay message shape

`attachments` on `MessageMeta` / `RelayMessage` should become:

```ts
attachments?: AttachmentRef[];
```

---

## R2 object layout

We will continue to use the `att/` prefix.

## Original object key

Recommended key format:

```text
att/{recipient}/{revTs}-{msgId}-{index}-{safeName}
```

Examples:

```text
att/iphone-abc/8234567890123-1f2e3d4c-01-photo.heic
att/iphone-abc/8234567890123-1f2e3d4c-02-notes.pdf
```

## Preview object key

Recommended key format:

```text
att/{recipient}/{revTs}-{msgId}-{index}-preview.jpg
```

Examples:

```text
att/iphone-abc/8234567890123-1f2e3d4c-01-preview.jpg
att/iphone-abc/8234567890123-1f2e3d4c-02-preview.jpg
```

## Key generation rules

- object keys are generated once per outgoing message attempt before CAS commit
- keys remain stable across CAS retries for that message send attempt
- only the `msg/...json` key is regenerated on CAS retry

---

## Supported attachment types for v1

Initial attachment UX should focus on common chat/media types:

- images
- videos
- audio
- generic files
- PDFs

The UI should classify attachments into render categories using `kind` + `content_type`.

## v1 exclusions

Out of scope for initial implementation:

- giant file workflows
- resumable uploads
- background continuation across app relaunch for huge transfers
- attachment encryption beyond existing bucket security model
- full document OCR/transcript indexing
- inline editing/annotation

---

## Send flow

## iOS -> relay -> plugin

1. user selects zero or more attachments in the composer
2. app creates local draft message + draft attachment state
3. app uploads all original attachment objects to R2
4. app optionally uploads preview/poster objects
5. app builds `AttachmentRef[]`
6. app appends the relay message JSON referencing those attachment objects
7. app performs head CAS update
8. if CAS fails, app retries message append using the same uploaded attachments and the same `AttachmentRef[]`
9. after success, local message becomes `sentToRelay`
10. normal confirmation/reconciliation flow continues

## Plugin/assistant -> relay -> iOS

1. OpenClaw produces a reply payload with text and zero or more media URLs/paths
2. `r2-relay-channel` normalizes the payload
3. plugin uploads each attachment to R2 original object keys
4. plugin optionally creates/uploads previews
5. plugin builds `AttachmentRef[]`
6. plugin sends one relay message containing:
   - final text body
   - full `attachments[]`
   - any existing `platform_data`

This should happen via payload-aware outbound delivery, not by splitting each attachment into separate relay messages.

---

## Receive flow

## iOS receive path

On sync ingest:

1. decode relay message including `attachments[]`
2. accept messages with attachments even when `body` is empty
3. create/update the message record
4. create/update attachment records in a dedicated attachment table
5. publish transcript updates

Important change from current behavior:

- attachment-only messages must not be dropped

## Plugin receive path

When the plugin receives a relay message from the app:

1. preserve the attachment manifest from `attachments[]`
2. materialize supported attachments to temp files when needed
3. build an inbound context for the agent that includes:
   - user text/caption
   - attachment manifest text
   - image model inputs where appropriate
   - local file paths for future tool/use-site handling where appropriate

Attachment relay support does **not** imply that every attachment should be blindly injected into the model. The plugin should separate:

- transport support
- agent/model ingestion policy

---

## Assistant-facing behavior

## Inbound app attachments to the agent

The agent should receive a concise attachment manifest in the prompt context, for example:

```text
Attachments:
1. photo.heic (image/heic, 3.1 MB)
2. notes.pdf (application/pdf, 420 KB)
```

Additionally:

- images should be passed as real image inputs when possible
- supported docs/audio may later be materialized for richer processing
- unsupported or non-ingested attachments should still appear in the manifest

## Outbound assistant attachments to the app

Assistant-generated `MEDIA:` outputs should become real relay attachments, not text artifacts.

The iOS app should never display raw `MEDIA:` lines in normal chat UX.

---

## Plugin design

## Capability changes

Update plugin capabilities to advertise media support.

Current:

```ts
media: false
```

Target:

```ts
media: true
```

Also add a protocol capability string to published identity metadata:

- `attachments:v1`

## Required outbound path

For this channel, implement payload-aware outbound delivery so one assistant reply can contain:

- text
- many attachments
- shared channel data

Recommended channel behavior:

- support `sendPayload(...)` for text + many attachments in one relay message
- do not rely only on one-media-at-a-time delivery helpers

## Service-level helpers

Recommended plugin helpers:

- `uploadRelayAttachment(...)`
- `uploadRelayAttachments(...)`
- `buildAttachmentRef(...)`
- `prepareInboundRelayAttachments(...)`

## Streaming rule

Assistant partial stream snapshots remain text-only.

Attachments belong only on the final committed message, never on partial `assistant_stream` snapshots.

---

## iOS architecture design

## Domain additions

Add first-class attachment domain models instead of embedding ad hoc dictionaries in UI state.

Recommended additions:

- `ChatAttachment`
- `DraftAttachment`
- `AttachmentKind`
- `AttachmentTransferState`

`ChatMessage` should gain:

```swift
let attachments: [ChatAttachment]
```

## Persistence

Add a dedicated attachment table.

Recommended table shape:

### `message_attachments`

- `messageID`
- `attachmentID`
- `objectKey`
- `previewObjectKey`
- `fileName`
- `mimeType`
- `sizeBytes`
- `sha256`
- `kind`
- `width`
- `height`
- `durationMS`
- `sortIndex`
- `transferState`
- `localCacheURL`
- `previewCacheURL`

This should be owned by `Data/` + `Services/`, not by feature views.

## Service additions

Recommended new service:

- `RelayAttachmentService`
  - upload original
  - upload preview/poster
  - download original
  - download preview
  - manage local attachment cache
  - infer metadata

Recommended repository/service changes:

- extend `RelayMessagingService`
- extend `RelaySyncEngine`
- extend transcript hydration in `AppDatabase`

---

## iOS UX design

## Composer

The composer should support:

- multi-select photos/videos
- file picker
- paste image/file
- optional camera capture later if not in first pass

The selected attachments should appear in a tray above the text field.

Each item should show:

- thumbnail for image/video where available
- file icon for generic files
- filename or type label
- remove affordance

One send action should send the text body as caption plus all selected attachments.

## Transcript rendering

### Images

- single image: large preview
- multiple images: grid
- tap to open full-screen viewer

### Videos

- poster preview with play affordance
- open playable viewer on tap

### Audio

- compact audio row
- initial version may open in system playback instead of custom inline player

### Files

- file card with icon, name, type, size
- tap to download/open/share

### Mixed content

- render text/caption first
- render attachment section below

## Transfer UX

Message-level states should distinguish:

- preparing
- uploading
- sending
- sentToRelay
- confirmed
- failed

We do not need per-byte giant-upload UX in v1. Simple, reliable state transitions are enough.

## Download strategy

Use lazy loading for received attachments:

- previews first where available
- originals on demand

Suggested v1 behavior:

- image preview can auto-load
- file/video/audio original loads on tap

---

## Preview policy

Previews are optional but recommended for good UX.

## v1 preview recommendations

- images: optional preview JPEG for faster transcript rendering
- videos: optional poster JPEG
- files: no uploaded preview required initially
- audio: no preview required initially

The system should function even when a message has only original objects and no preview objects.

---

## Security / integrity model for v1

For initial implementation, rely on existing shared bucket credentials and relay trust model.

Recommended integrity fields:

- `size`
- `sha256`
- `content_type`

Validation rules:

- trust object keys from relay metadata
- do not trust file extension alone for rendering behavior
- verify `sha256` after download when practical

No additional per-attachment encryption layer is required in v1.

---

## Implementation checkpoints

## Plugin / TypeScript

### `r2-relay-channel/src/protocol.ts`

- define canonical `AttachmentRef`
- update `MessageMeta.attachments`
- add attachment capability string(s)
- add deterministic attachment key helpers

### `r2-relay-channel/src/service.ts`

- add attachment upload helpers
- update `sendMessage(...)` to accept canonical `AttachmentRef[]`
- ensure CAS retries reuse uploaded attachments

### `r2-relay-channel/src/channel.ts`

- advertise `media: true`
- implement payload-aware outbound send for text + many attachments in one relay message
- add inbound attachment preparation for agent dispatch
- keep partial stream snapshots text-only

## iOS / Swift

### `ClawChat/ClawChat/Services/Relay/RelayMessageModels.swift`

- define `RelayAttachment`
- add `attachments` to `RelayMessage`

### `ClawChat/ClawChat/Services/Relay/RelayMessagingService.swift`

- add send path for text + attachments
- add upload helpers or delegate to `RelayAttachmentService`
- keep attachment refs stable across CAS retries

### `ClawChat/ClawChat/Services/Relay/RelaySyncEngine.swift`

- extend send path to support draft attachments
- coordinate optimistic local message + attachment state

### `ClawChat/ClawChat/Data/Database/AppDatabase.swift`

- add attachment table
- ingest attachment-only messages
- hydrate transcript messages with attachments

### Feature/UI work

- extend chat message domain/view state with attachments
- add composer attachment tray
- add transcript attachment rendering
- add tap-to-open/download behavior

---

## Recommended implementation order

1. define canonical `AttachmentRef` on both sides
2. add iOS decoding/storage support for inbound attachments
3. allow attachment-only message ingest
4. implement plugin outbound attachment bundling for assistant replies
5. implement iOS send flow for text + attachments
6. implement transcript rendering and open/download behavior
7. optionally add preview generation/upload

This order enables early end-to-end testing while keeping risk localized.

---

## Non-goals for the first implementation

- giant-file architecture
- resumable uploads
- background transfer daemon design
- per-attachment encryption
- offline-first attachment sync strategy
- OCR/transcript indexing/search
- threaded attachment comments or per-attachment reactions

The first release should prioritize correctness, natural chat UX, and protocol clarity.
