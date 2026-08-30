export type AttachmentKind = "image" | "video" | "audio" | "file" | "unknown";

export interface AttachmentRef {
  id: string;
  key: string;
  file_name: string | null;
  content_type: string | null;
  size: number | null;
  sha256: string | null;
  kind: AttachmentKind;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  preview_image_key: string | null;
  preview_image_type: string | null;
  preview_size: number | null;
}

// --- v3 Route ---

export interface RelayRoute {
  agent_id: string;
  conversation_id?: string | null;
  instance_id?: string | null;
}

// --- v3 Content (discriminated union) ---

export interface RelayTextContent {
  type: "text";
  text: string;
  attachments?: AttachmentRef[] | null;
}

export interface RelayReactionContent {
  type: "reaction";
  target_msg_id: string;
  emoji: string;
  remove?: boolean | null;
}

export interface RelayApprovalRequestContent {
  type: "approval_request";
  approval_id: string;
  approval_kind: "exec" | "tool" | "custom";
  title: string;
  body?: string | null;
  allowed_decisions: string[];
  metadata?: Record<string, unknown> | null;
}

export interface RelayApprovalResponseContent {
  type: "approval_response";
  approval_id: string;
  decision: string;
  metadata?: Record<string, unknown> | null;
}

export interface RelaySystemContent {
  type: "system";
  event: string;
  data?: Record<string, unknown> | null;
}

export type RelayContent =
  | RelayTextContent
  | RelayReactionContent
  | RelayApprovalRequestContent
  | RelayApprovalResponseContent
  | RelaySystemContent;

// --- v3 Delivery ---

export interface RelayDeliveryStream {
  stream_id: string;
  seq: number;
  state: "partial" | "final";
}

export interface RelayDelivery {
  stream?: RelayDeliveryStream | null;
}

// --- v3 Message Status ---

export interface RelayMessageStatus {
  state: "pending" | "processing" | "done" | "error";
  processed_at?: number | null;
  processed_by?: string | null;
  error?: string | null;
}

// --- v3 Message ---

export interface RelayMessage {
  msg_id: string;
  from: string;
  to: string;
  ts_sent: number;
  prev_key: string | null;
  route: RelayRoute;
  content: RelayContent;
  delivery?: RelayDelivery | null;
  status?: RelayMessageStatus | null;
  size?: number | null;
}

export interface HeadDoc {
  head_key: string;
  head_msg_id: string;
  head_ts: number;
}

// --- v3 Identity Doc ---

export interface RelayCapabilities {
  messaging: {
    text: boolean;
    streaming: boolean;
    reactions: boolean;
    system_events: boolean;
  };
  conversations: {
    list: boolean;
    create: boolean;
    reset: boolean;
    archive: boolean;
    threading: boolean;
  };
  agents: {
    list: boolean;
    multiple: boolean;
    switch: boolean;
    per_agent_models: boolean;
  };
  attachments?: {
    supported: boolean;
    kinds: AttachmentKind[];
    max_bytes_by_kind?: Partial<Record<AttachmentKind, number>>;
    oversize_behavior?: "reject" | "drop" | "link" | "summarize";
  } | null;
  approvals?: {
    exec: boolean;
    tool: boolean;
    custom: boolean;
  } | null;
  extensions?: Record<string, unknown> | null;
}

export interface ModelDescriptor {
  id: string;
  label?: string | null;
  provider?: string | null;
}

export interface AgentDescriptor {
  id: string;
  display_name?: string | null;
  description?: string | null;
  is_default: boolean;
  models?: {
    available: ModelDescriptor[];
    default?: string | null;
  } | null;
  default_route: RelayRoute;
  capabilities?: Partial<RelayCapabilities> | null;
}

export interface ConversationSource {
  channel: string;
  chat_kind?: "dm" | "group" | "channel" | "thread" | null;
  account_id?: string | null;
  account_display?: string | null;
  space_id?: string | null;
  space_display?: string | null;
  chat_id?: string | null;
  chat_display?: string | null;
  participant_id?: string | null;
  participant_display?: string | null;
  thread_id?: string | null;
  thread_display?: string | null;
  sharing?: "private" | "shared" | "per-user" | null;
}

export interface ConversationDescriptor {
  id: string;
  display_title?: string | null;
  route: RelayRoute;
  source?: ConversationSource | null;
  updated_at?: number | null;
}

export interface ServerLimits {
  inbound_attachment_max_bytes?: {
    image: number;
    video: number;
    audio: number;
    file: number;
  } | null;
  oversize_attachment_behavior?: string | null;
}

export interface IdentityDoc {
  peer: string;
  display_name: string;
  role: "server" | "client";
  last_seen: number;
  protocol: { name: "r2-relay"; version: number };
  software: { id: string; name?: string | null; version?: string | null };
  capabilities: RelayCapabilities;
  limits?: ServerLimits | null;
  agents: AgentDescriptor[];
  conversations: ConversationDescriptor[];
}

export interface InboxMessage {
  key: string;
  message: RelayMessage;
}

export interface InboxBatch {
  head: HeadDoc | null;
  messages: InboxMessage[];
  checkpointHeadKey: string | null;
}

export interface SendMessageOptions {
  route: RelayRoute;
  content: RelayContent;
  delivery?: RelayDelivery | null;
}

export interface SendMessageResult {
  key: string;
  messageId: string;
}

export interface RelayRetentionConfig {
  msg?: number;
  att?: number;
  identity?: number;
  head?: number;
}

export interface SweepRuleSummary {
  prefix: string;
  scanned: number;
  deleted: number;
}

export interface RelayCheckpointState {
  lastHeadKey: string | null;
  recentMessageIds: string[];
  recentObjectKeys: string[];
  lastPollAt: number | null;
  lastInboundAt: number | null;
}
