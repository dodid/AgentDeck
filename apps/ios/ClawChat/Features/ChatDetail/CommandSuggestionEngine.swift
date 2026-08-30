import Foundation

struct CommandSuggestionViewData: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let sectionTitle: String
    let argumentsHint: String?
}

struct ModelSuggestionViewData: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let sectionTitle: String
}

struct CommandSuggestionEngine {
    func commandSuggestions(for draft: String, platform: String) -> [CommandSuggestionViewData] {
        guard let parsed = ParsedAgentCommand.parse(draft), !parsed.isModelCommand else { return [] }
        if parsed.spec != nil {
            return []
        }
        return AgentCommandSpec.commands(for: platform)
            .filter { parsed.commandToken.isEmpty || $0.aliases.contains(where: { $0.hasPrefix(parsed.commandToken) }) }
            .map {
                CommandSuggestionViewData(
                    id: $0.id,
                    title: $0.trigger,
                    subtitle: $0.localizedDescription,
                    sectionTitle: commandSectionTitle(for: $0.category),
                    argumentsHint: $0.argumentsHint
                )
            }
    }

    func modelSuggestions(for draft: String, models: [ModelDescriptor]) -> [ModelSuggestionViewData] {
        guard let parsed = ParsedAgentCommand.parse(draft), parsed.isModelCommand else { return [] }
        let query = parsed.arguments.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty, models.contains(where: { $0.id.lowercased() == query }) {
            return []
        }
        return models
            .filter {
                query.isEmpty ||
                $0.id.lowercased().contains(query) ||
                ($0.label?.lowercased().contains(query) ?? false)
            }
            .map {
                ModelSuggestionViewData(
                    id: $0.id,
                    title: $0.id,
                    subtitle: $0.provider ?? ($0.label ?? $0.id),
                    sectionTitle: $0.provider?.isEmpty == false ? $0.provider! : String(localized: "Other")
                )
            }
    }

    private func commandSectionTitle(for category: String) -> String {
        switch category {
        case "status":
            return String(localized: "Status")
        case "options":
            return String(localized: "Options")
        case "session":
            return String(localized: "Session")
        case "management":
            return String(localized: "Management")
        case "media":
            return String(localized: "Media")
        case "tools":
            return String(localized: "Tools")
        default:
            return category.capitalized
        }
    }
}
