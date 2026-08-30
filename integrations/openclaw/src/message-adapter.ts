import { defineChannelMessageAdapter } from "openclaw/plugin-sdk/channel-message";
import type { MessageReceipt, MessageReceiptSourceResult } from "openclaw/plugin-sdk/channel-message";
import { sendRelayPayloadMessage } from "./outbound.js";

function asMessageResult(result: MessageReceiptSourceResult & { messageId: string }) {
  const sentAt = result.timestamp ?? Date.now();
  const receipt: MessageReceipt = {
    primaryPlatformMessageId: result.messageId,
    platformMessageIds: [result.messageId],
    parts: [{
      platformMessageId: result.messageId,
      kind: "text",
      index: 0,
      raw: result,
    }],
    sentAt,
    raw: [result],
  };
  return { receipt, messageId: result.messageId };
}

export const r2RelayMessageAdapter = defineChannelMessageAdapter({
  id: "r2-relay-channel",
  durableFinal: {
    capabilities: {
      text: true,
      media: true,
      payload: true,
    },
  },
  send: {
    text: async ({ cfg, to, text, accountId }) => asMessageResult(await sendRelayPayloadMessage({
      cfg: cfg as Record<string, unknown>,
      to,
      payload: { text },
      accountId,
      source: "message.text",
    })),
    media: async ({ cfg, to, text, mediaUrl, accountId, mediaAccess, mediaLocalRoots, mediaReadFile }) =>
      asMessageResult(await sendRelayPayloadMessage({
        cfg: cfg as Record<string, unknown>,
        to,
        payload: { text, mediaUrl },
        accountId,
        source: "message.media",
        meta: { mediaAccess, mediaLocalRoots, mediaReadFile },
      })),
    payload: async ({ cfg, to, payload, accountId, mediaAccess, mediaLocalRoots, mediaReadFile }) =>
      asMessageResult(await sendRelayPayloadMessage({
        cfg: cfg as Record<string, unknown>,
        to,
        payload,
        accountId,
        source: "message.payload",
        meta: { mediaAccess, mediaLocalRoots, mediaReadFile },
      })),
  },
});
