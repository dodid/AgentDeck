declare module "openclaw/plugin-sdk/outbound-media" {
  import type { OutboundMediaAccess } from "openclaw/plugin-sdk/media-runtime";

  export function loadOutboundMediaFromUrl(
    mediaUrl: string,
    options?: {
      maxBytes?: number;
      mediaAccess?: OutboundMediaAccess;
      mediaLocalRoots?: readonly string[] | "any";
      mediaReadFile?: (filePath: string) => Promise<Buffer>;
      workspaceDir?: string;
    },
  ): Promise<{
    buffer: Buffer;
    contentType?: string;
    fileName?: string;
  }>;
}
