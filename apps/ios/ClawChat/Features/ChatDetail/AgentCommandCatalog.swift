import Foundation

struct AgentCommandSpec: Identifiable, Equatable, Sendable {
    let id: String
    let trigger: String
    let description: String
    let aliases: [String]
    let category: String
    let argumentsHint: String?

    var localizedDescription: String {
        String(localized: String.LocalizationValue(description))
    }

    static let openClaw: [AgentCommandSpec] = [
        .init(id: "help", trigger: "/help", description: "Show available commands.", aliases: ["/help"], category: "status", argumentsHint: nil),
        .init(id: "commands", trigger: "/commands", description: "List all slash commands.", aliases: ["/commands"], category: "status", argumentsHint: nil),
        .init(id: "tools", trigger: "/tools", description: "List available runtime tools.", aliases: ["/tools"], category: "status", argumentsHint: nil),
        .init(id: "status", trigger: "/status", description: "Show current status.", aliases: ["/status"], category: "status", argumentsHint: nil),
        .init(id: "context", trigger: "/context", description: "Explain how context is built and used.", aliases: ["/context"], category: "status", argumentsHint: nil),
        .init(id: "export-session", trigger: "/export-session", description: "Export current session to HTML file with full system prompt.", aliases: ["/export-session", "/export"], category: "status", argumentsHint: nil),
        .init(id: "whoami", trigger: "/whoami", description: "Show your sender id.", aliases: ["/whoami", "/id"], category: "status", argumentsHint: nil),
        .init(id: "session-target", trigger: "/session-target", description: "Show cron and webhook targets for the current session.", aliases: ["/session-target"], category: "status", argumentsHint: nil),

        .init(id: "session", trigger: "/session", description: "Manage session-level settings (for example /session idle).", aliases: ["/session"], category: "session", argumentsHint: "[setting]"),
        .init(id: "stop", trigger: "/stop", description: "Stop the current run.", aliases: ["/stop"], category: "session", argumentsHint: nil),
        .init(id: "model", trigger: "/model", description: "Show or set the model.", aliases: ["/model"], category: "options", argumentsHint: "<id>"),
        .init(id: "models", trigger: "/models", description: "List model providers or provider models.", aliases: ["/models"], category: "options", argumentsHint: "[provider]"),
        .init(id: "new", trigger: "/new", description: "Start a new session.", aliases: ["/new"], category: "session", argumentsHint: nil),
        .init(id: "reset", trigger: "/reset", description: "Reset the current session.", aliases: ["/reset"], category: "session", argumentsHint: nil),
        .init(id: "compact", trigger: "/compact", description: "Compact the session context.", aliases: ["/compact"], category: "session", argumentsHint: nil),
        .init(id: "usage", trigger: "/usage", description: "Usage footer or cost summary.", aliases: ["/usage"], category: "options", argumentsHint: nil),
        .init(id: "think", trigger: "/think", description: "Set thinking level.", aliases: ["/think", "/thinking", "/t"], category: "options", argumentsHint: "<low|med|high>"),
        .init(id: "verbose", trigger: "/verbose", description: "Toggle verbose mode.", aliases: ["/verbose", "/v"], category: "options", argumentsHint: "<on|off>"),
        .init(id: "fast", trigger: "/fast", description: "Toggle fast mode.", aliases: ["/fast"], category: "options", argumentsHint: "<on|off>"),
        .init(id: "reasoning", trigger: "/reasoning", description: "Toggle reasoning visibility.", aliases: ["/reasoning", "/reason"], category: "options", argumentsHint: "<on|off>"),
        .init(id: "elevated", trigger: "/elevated", description: "Toggle elevated mode.", aliases: ["/elevated", "/elev"], category: "options", argumentsHint: "<on|off>"),
        .init(id: "exec", trigger: "/exec", description: "Set exec defaults for this session.", aliases: ["/exec"], category: "options", argumentsHint: "[policy]"),
        .init(id: "queue", trigger: "/queue", description: "Adjust queue settings.", aliases: ["/queue"], category: "options", argumentsHint: "[setting]"),

        .init(id: "allowlist", trigger: "/allowlist", description: "List/add/remove allowlist entries.", aliases: ["/allowlist"], category: "management", argumentsHint: "[text]"),
        .init(id: "approve", trigger: "/approve", description: "Approve or deny exec requests.", aliases: ["/approve"], category: "management", argumentsHint: nil),
        .init(id: "subagents", trigger: "/subagents", description: "List, kill, log, spawn, or steer subagent runs for this session.", aliases: ["/subagents"], category: "management", argumentsHint: "[action]"),
        .init(id: "acp", trigger: "/acp", description: "Manage ACP sessions and runtime options.", aliases: ["/acp"], category: "management", argumentsHint: "[action]"),
        .init(id: "focus", trigger: "/focus", description: "Bind this thread or conversation to a session target.", aliases: ["/focus"], category: "management", argumentsHint: "[target]"),
        .init(id: "unfocus", trigger: "/unfocus", description: "Remove the current thread or conversation binding.", aliases: ["/unfocus"], category: "management", argumentsHint: nil),
        .init(id: "agents", trigger: "/agents", description: "List thread-bound agents for this session.", aliases: ["/agents"], category: "management", argumentsHint: nil),
        .init(id: "kill", trigger: "/kill", description: "Kill a running subagent (or all).", aliases: ["/kill"], category: "management", argumentsHint: "[id|all]"),
        .init(id: "steer", trigger: "/steer", description: "Send guidance to a running subagent.", aliases: ["/steer", "/tell"], category: "management", argumentsHint: "<message>"),
        .init(id: "activation", trigger: "/activation", description: "Set group activation mode.", aliases: ["/activation"], category: "management", argumentsHint: "[mode]"),
        .init(id: "send", trigger: "/send", description: "Set send policy.", aliases: ["/send"], category: "management", argumentsHint: "[policy]"),

        .init(id: "tts", trigger: "/tts", description: "Control text-to-speech (TTS).", aliases: ["/tts"], category: "media", argumentsHint: "[option]"),

        .init(id: "skill", trigger: "/skill", description: "Run a skill by name.", aliases: ["/skill"], category: "tools", argumentsHint: "<name>"),
        .init(id: "btw", trigger: "/btw", description: "Ask a side question without changing future session context.", aliases: ["/btw"], category: "tools", argumentsHint: "<question>"),
        .init(id: "restart", trigger: "/restart", description: "Restart OpenClaw.", aliases: ["/restart"], category: "tools", argumentsHint: nil)
    ]

    static let hermesMessaging: [AgentCommandSpec] = [
        .init(id: "hermes-new", trigger: "/new", description: "Start a new conversation.", aliases: ["/new"], category: "session", argumentsHint: nil),
        .init(id: "hermes-reset", trigger: "/reset", description: "Reset conversation history.", aliases: ["/reset"], category: "session", argumentsHint: nil),
        .init(id: "hermes-status", trigger: "/status", description: "Show session info.", aliases: ["/status"], category: "session", argumentsHint: nil),
        .init(id: "hermes-stop", trigger: "/stop", description: "Kill all running background processes.", aliases: ["/stop"], category: "session", argumentsHint: nil),
        .init(id: "hermes-retry", trigger: "/retry", description: "Retry the last message.", aliases: ["/retry"], category: "session", argumentsHint: nil),
        .init(id: "hermes-undo", trigger: "/undo", description: "Remove the last exchange.", aliases: ["/undo"], category: "session", argumentsHint: nil),
        .init(id: "hermes-title", trigger: "/title", description: "Set or show the session title.", aliases: ["/title"], category: "session", argumentsHint: "[name]"),
        .init(id: "hermes-branch", trigger: "/branch", description: "Branch the current session (explore a different path).", aliases: ["/branch", "/fork"], category: "session", argumentsHint: "[name]"),
        .init(id: "hermes-compress", trigger: "/compress", description: "Manually compress conversation context.", aliases: ["/compress"], category: "session", argumentsHint: "[focus topic]"),
        .init(id: "hermes-rollback", trigger: "/rollback", description: "List or restore filesystem checkpoints.", aliases: ["/rollback"], category: "session", argumentsHint: "[number]"),
        .init(id: "hermes-background", trigger: "/background", description: "Run a prompt in the background.", aliases: ["/background", "/bg", "/btw"], category: "session", argumentsHint: "<prompt>"),
        .init(id: "hermes-queue", trigger: "/queue", description: "Queue a prompt for the next turn without interrupting the current one.", aliases: ["/queue", "/q"], category: "session", argumentsHint: "<prompt>"),
        .init(id: "hermes-steer", trigger: "/steer", description: "Inject a message after the next tool call without interrupting.", aliases: ["/steer"], category: "session", argumentsHint: "<prompt>"),
        .init(id: "hermes-agents", trigger: "/agents", description: "Show active agents and running tasks.", aliases: ["/agents", "/tasks"], category: "session", argumentsHint: nil),
        .init(id: "hermes-resume", trigger: "/resume", description: "Resume a previously named session.", aliases: ["/resume"], category: "session", argumentsHint: "[name]"),
        .init(id: "hermes-goal", trigger: "/goal", description: "Set a standing goal Hermes works toward across turns.", aliases: ["/goal"], category: "session", argumentsHint: "[text|status|pause|resume|clear]"),

        .init(id: "hermes-model", trigger: "/model", description: "Show or change the model.", aliases: ["/model", "/provider"], category: "configuration", argumentsHint: "[provider:model]"),
        .init(id: "hermes-personality", trigger: "/personality", description: "Set a personality overlay for the session.", aliases: ["/personality"], category: "configuration", argumentsHint: "[name]"),
        .init(id: "hermes-fast", trigger: "/fast", description: "Toggle fast mode.", aliases: ["/fast"], category: "configuration", argumentsHint: "[normal|fast|status]"),
        .init(id: "hermes-reasoning", trigger: "/reasoning", description: "Change reasoning effort or toggle reasoning display.", aliases: ["/reasoning"], category: "configuration", argumentsHint: "[level|show|hide]"),
        .init(id: "hermes-voice", trigger: "/voice", description: "Control spoken replies in chat.", aliases: ["/voice"], category: "configuration", argumentsHint: "[on|off|tts|join|channel|leave|status]"),
        .init(id: "hermes-footer", trigger: "/footer", description: "Toggle the runtime-metadata footer on final replies.", aliases: ["/footer"], category: "configuration", argumentsHint: "[on|off|status]"),
        .init(id: "hermes-yolo", trigger: "/yolo", description: "Toggle YOLO mode (skip all dangerous command approvals).", aliases: ["/yolo"], category: "configuration", argumentsHint: nil),

        .init(id: "hermes-curator", trigger: "/curator", description: "Background skill maintenance controls.", aliases: ["/curator"], category: "tools", argumentsHint: "[status|run|pin|archive]"),
        .init(id: "hermes-kanban", trigger: "/kanban", description: "Drive the multi-profile collaboration board from chat.", aliases: ["/kanban"], category: "tools", argumentsHint: "<action>"),
        .init(id: "hermes-reload-mcp", trigger: "/reload-mcp", description: "Reload MCP servers from config.", aliases: ["/reload-mcp", "/reload_mcp"], category: "tools", argumentsHint: nil),
        .init(id: "hermes-reload-skills", trigger: "/reload-skills", description: "Re-scan installed skills for newly added or removed skills.", aliases: ["/reload-skills", "/reload_skills"], category: "tools", argumentsHint: nil),

        .init(id: "hermes-help", trigger: "/help", description: "Show messaging help.", aliases: ["/help"], category: "info", argumentsHint: nil),
        .init(id: "hermes-commands", trigger: "/commands", description: "Browse all commands and skills.", aliases: ["/commands"], category: "info", argumentsHint: "[page]"),
        .init(id: "hermes-usage", trigger: "/usage", description: "Show token usage, estimated cost breakdown, and context state.", aliases: ["/usage"], category: "info", argumentsHint: nil),
        .init(id: "hermes-insights", trigger: "/insights", description: "Show usage analytics.", aliases: ["/insights"], category: "info", argumentsHint: "[days]"),
        .init(id: "hermes-profile", trigger: "/profile", description: "Show active profile name and home directory.", aliases: ["/profile"], category: "info", argumentsHint: nil),
        .init(id: "hermes-debug", trigger: "/debug", description: "Upload debug report (system info and logs) and get shareable links.", aliases: ["/debug"], category: "info", argumentsHint: nil),

        .init(id: "hermes-approve", trigger: "/approve", description: "Approve and execute a pending dangerous command.", aliases: ["/approve"], category: "management", argumentsHint: "[session|always]"),
        .init(id: "hermes-deny", trigger: "/deny", description: "Reject a pending dangerous command.", aliases: ["/deny"], category: "management", argumentsHint: nil),
        .init(id: "hermes-sethome", trigger: "/sethome", description: "Mark the current chat as the platform home channel for deliveries.", aliases: ["/sethome", "/set-home"], category: "management", argumentsHint: nil),
        .init(id: "hermes-topic", trigger: "/topic", description: "Manage Telegram DM multi-session topic mode.", aliases: ["/topic"], category: "management", argumentsHint: "[off|help|session-id]"),
        .init(id: "hermes-update", trigger: "/update", description: "Update Hermes Agent to the latest version.", aliases: ["/update"], category: "management", argumentsHint: nil),
        .init(id: "hermes-restart", trigger: "/restart", description: "Gracefully restart the gateway after draining active runs.", aliases: ["/restart"], category: "management", argumentsHint: nil)
    ]

    static let all: [AgentCommandSpec] = openClaw + hermesMessaging

    static func commands(for platform: String) -> [AgentCommandSpec] {
        switch platform.lowercased() {
        case "openclaw":
            return openClaw
        case "hermes":
            return hermesMessaging
        default:
            return []
        }
    }
}

struct ParsedAgentCommand: Sendable {
    let raw: String
    let commandToken: String
    let arguments: String
    let spec: AgentCommandSpec?

    var isModelCommand: Bool {
        commandToken == "/model"
    }

    static func parse(_ raw: String) -> ParsedAgentCommand? {
        let trimmed = raw.trimmingCharacters(in: .newlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: { $0.isWhitespace })
        let commandToken = parts.first.map(String.init) ?? ""
        let arguments = parts.count > 1 ? String(parts[1]) : ""
        let spec = AgentCommandSpec.all.first { cmd in
            cmd.aliases.contains(commandToken)
        }
        return ParsedAgentCommand(raw: raw, commandToken: commandToken, arguments: arguments, spec: spec)
    }
}
