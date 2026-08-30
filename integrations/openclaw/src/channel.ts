import { DEFAULT_ACCOUNT_ID } from "openclaw/plugin-sdk/account-id";
import {
  buildBaseChannelStatusSummary,
  collectStatusIssuesFromLastError,
} from "openclaw/plugin-sdk/status-helpers";
import { runPassiveAccountLifecycle } from "openclaw/plugin-sdk/channel-lifecycle";
import type { ChannelPlugin } from "openclaw/plugin-sdk";
import {
  r2RelayChannelConfigSchema,
  resolveR2RelayAccount,
  type ResolvedR2RelayAccount,
  listR2RelayAccountIds,
} from "./config.js";
import { r2RelaySetupAdapter, r2RelaySetupWizard } from "./setup.js";
import { loadCheckpointState } from "./checkpoint-store.js";
import { formatInboundRelayBody, classifyInboundRelayMessageFailure, dispatchInboundMessage } from "./inbound.js";
import {
  clearService,
  createDefaultRuntimeState,
  getOrCreateService,
  pollRelayInbox,
  redactEndpoint,
  runSweeperLoop,
  setRuntimeSnapshot,
  touchRuntime,
  type RelayRuntimeState,
} from "./lifecycle.js";
import { r2RelayMessageAdapter } from "./message-adapter.js";
import { getRelayRuntime } from "./runtime.js";
import { syncPublishedIdentity } from "./session-publication.js";
import { formatRelayTargetHint, parseRelayTarget } from "./target.js";

function jsonResult(payload: Record<string, unknown>) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(payload, null, 2),
      },
    ],
    details: payload,
    channelData: payload,
  };
}

function readStringParam(
  params: Record<string, unknown>,
  key: string,
  options?: { required?: boolean },
): string {
  const value = params[key];
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed.length > 0 || !options?.required) {
      return trimmed;
    }
  }
  if (options?.required) {
    throw new Error(`Missing required parameter: ${key}`);
  }
  return "";
}

function readBooleanParam(params: Record<string, unknown>, key: string): boolean {
  const value = params[key];
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "y", "on"].includes(normalized)) {
      return true;
    }
    if (["0", "false", "no", "n", "off", ""].includes(normalized)) {
      return false;
    }
  }
  return false;
}

function readReactionParams(
  params: Record<string, unknown>,
  options?: { removeErrorMessage?: string },
): { emoji: string; remove: boolean; isEmpty: boolean } {
  const emoji = readStringParam(params, "emoji") || readStringParam(params, "reaction");
  const remove = readBooleanParam(params, "remove");
  const isEmpty = emoji.length === 0;

  if (remove && isEmpty) {
    throw new Error(options?.removeErrorMessage ?? "remove=true requires a specific emoji.");
  }
  if (!remove && isEmpty) {
    throw new Error("Missing required parameter: emoji");
  }

  return { emoji, remove, isEmpty };
}

function agentIdFromConversationId(conversationId: string | null | undefined): string | null {
  const normalized = conversationId?.trim();
  if (!normalized) {
    return null;
  }
  const parts = normalized.split(":");
  if (parts.length >= 2 && parts[0] === "agent" && parts[1]?.trim()) {
    return parts[1].trim();
  }
  return null;
}

type RelayApprovalCapability = {
  getExecInitiatingSurfaceState: (params: {
    cfg: Parameters<typeof resolveR2RelayAccount>[0]["cfg"];
    accountId?: string | null;
    action: "approve";
  }) => { kind: "enabled" | "disabled" };
};

type RelayChannelPlugin = ChannelPlugin<ResolvedR2RelayAccount> & {
  approvalCapability: RelayApprovalCapability;
};

export const r2RelayPlugin: RelayChannelPlugin = {
  id: "r2-relay-channel",
  meta: {
    id: "r2-relay-channel",
    label: "R2 Relay",
    selectionLabel: "R2 Relay",
    docsPath: "/channels/r2-relay-channel",
    docsLabel: "r2-relay-channel",
    blurb: "Cloudflare R2-backed relay channel for direct text messaging.",
    order: 120,
  },
  capabilities: {
    chatTypes: ["direct"],
    reactions: true,
    media: true,
  },
  approvalCapability: {
    getExecInitiatingSurfaceState: ({
      cfg,
      accountId,
    }: {
      cfg: Parameters<typeof resolveR2RelayAccount>[0]["cfg"];
      accountId?: string | null;
      action: "approve";
    }) => {
      const account = resolveR2RelayAccount({ cfg, accountId });
      if (!account.enabled || !account.configured) {
        return { kind: "disabled" as const };
      }
      return { kind: "enabled" as const };
    },
  },
  reload: { configPrefixes: ["channels.r2-relay-channel"] },
  configSchema: r2RelayChannelConfigSchema,
  setupWizard: r2RelaySetupWizard,
  setup: r2RelaySetupAdapter,
  config: {
    listAccountIds: (cfg) => listR2RelayAccountIds(cfg),
    resolveAccount: (cfg, accountId) => resolveR2RelayAccount({ cfg, accountId }),
    defaultAccountId: () => DEFAULT_ACCOUNT_ID,
    isConfigured: (account) => account.configured,
    describeAccount: (account) => ({
      accountId: account.accountId,
      enabled: account.enabled,
      configured: account.configured,
      serverId: account.serverId,
      bucket: account.bucket,
      endpoint: redactEndpoint(account.endpoint),
    }),
  },
  actions: {
    describeMessageTool: () => ({
      actions: ["react"],
    }),
    supportsAction: ({ action }) => action === "react",
    handleAction: async ({ action, params, cfg, accountId }) => {
      const account = resolveR2RelayAccount({ cfg, accountId });
      const service = getOrCreateService(account);

      if (action === "react") {
        const to = readStringParam(params, "to", { required: true });
        const messageId = readStringParam(params, "messageId", { required: true });
        const reaction = readReactionParams(params, {
          removeErrorMessage: "R2 Relay reactions support remove=true only with a specific emoji.",
        });
        const target = parseRelayTarget(to);

        const result = await service.sendMessage(
          target.peer,
          {
            route: {
              agent_id: target.conversationId ? agentIdFromConversationId(target.conversationId) ?? "main" : "main",
              conversation_id: target.conversationId ?? null,
              instance_id: null,
            },
            content: {
              type: "reaction",
              target_msg_id: messageId,
              emoji: reaction.emoji || "✅",
              remove: reaction.remove || reaction.isEmpty,
            },
          },
        );

        touchRuntime(account.accountId, {
          lastOutboundAt: Date.now(),
          lastError: null,
        });

        return jsonResult({
          ok: true,
          channel: "r2-relay-channel",
          action: "react",
          to: to.trim(),
          messageId: result.messageId,
          targetMessageId: messageId,
          emoji: reaction.emoji,
          remove: reaction.remove || reaction.isEmpty,
        });
      }

      throw new Error(`Unsupported r2-relay-channel action: ${action}`);
    },
  },
  messaging: {
    normalizeTarget: (target) => target.trim(),
    targetResolver: {
      looksLikeId: (input) => Boolean(input.trim()),
      hint: `${formatRelayTargetHint()} or <peer>`,
    },
  },
  message: r2RelayMessageAdapter,
  status: {
    defaultRuntime: createDefaultRuntimeState(DEFAULT_ACCOUNT_ID) as any,
    collectStatusIssues: (accounts) => collectStatusIssuesFromLastError("r2-relay-channel", accounts),
    buildChannelSummary: ({ snapshot }) => {
      const extended = snapshot as typeof snapshot & Partial<RelayRuntimeState>;
      return {
        ...buildBaseChannelStatusSummary(snapshot),
        serverId: extended.serverId ?? null,
        bucket: extended.bucket ?? null,
        endpoint: extended.endpoint ?? null,
        lastPollAt: extended.lastPollAt ?? null,
        checkpointHeadKey: extended.checkpointHeadKey ?? null,
        lastInboundAt: extended.lastInboundAt ?? null,
        lastOutboundAt: extended.lastOutboundAt ?? null,
      };
    },
    buildAccountSnapshot: ({ account, runtime }) => {
      const extendedRuntime = (runtime ?? null) as Partial<RelayRuntimeState> | null;
      return {
        accountId: account.accountId,
        enabled: account.enabled,
        configured: account.configured,
        running: runtime?.running ?? false,
        lastStartAt: runtime?.lastStartAt ?? null,
        lastStopAt: runtime?.lastStopAt ?? null,
        lastError: runtime?.lastError ?? null,
        lastPollAt: extendedRuntime?.lastPollAt ?? null,
        lastInboundAt: extendedRuntime?.lastInboundAt ?? null,
        lastOutboundAt: extendedRuntime?.lastOutboundAt ?? null,
        serverId: account.serverId,
        bucket: account.bucket,
        endpoint: redactEndpoint(account.endpoint),
        checkpointHeadKey: extendedRuntime?.checkpointHeadKey ?? null,
      };
    },
  },
  gateway: {
    startAccount: async (ctx) => {
      const account = ctx.account;
      const runtime = createDefaultRuntimeState(account.accountId);
      runtime.serverId = account.serverId;
      runtime.bucket = account.bucket;
      runtime.endpoint = redactEndpoint(account.endpoint);
      setRuntimeSnapshot(account.accountId, runtime);
      ctx.setStatus({
        accountId: account.accountId,
      } as any);

      return runPassiveAccountLifecycle({
        abortSignal: ctx.abortSignal,
        start: async () => {
          const service = getOrCreateService(account);
          await syncPublishedIdentity(service, account, true);
          void runSweeperLoop({
            account,
            service,
            abortSignal: ctx.abortSignal,
            log: ctx.log,
          });
          touchRuntime(account.accountId, {
            running: true,
            lastStartAt: Date.now(),
            lastError: null,
            serverId: account.serverId,
            bucket: account.bucket,
            endpoint: redactEndpoint(account.endpoint),
          });
          ctx.setStatus({
            accountId: account.accountId,
          } as any);

          const state = await loadCheckpointState(account.accountId);
          await pollRelayInbox({
            cfg: ctx.cfg as any,
            account,
            service,
            abortSignal: ctx.abortSignal,
            log: ctx.log,
            setStatus: ctx.setStatus as any,
            state,
            syncPublishedIdentity,
            dispatchInboundMessage,
            formatInboundRelayBody,
            classifyInboundRelayMessageFailure,
          });
          return { service };
        },
        stop: async () => {
          clearService(account.accountId);
          touchRuntime(account.accountId, {
            running: false,
            lastStopAt: Date.now(),
          });
        },
      });
    },
  },
};
