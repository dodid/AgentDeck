import SwiftUI

struct ComposerSuggestionsView: View {
    let commandSuggestions: [CommandSuggestionViewData]
    let modelSuggestions: [ModelSuggestionViewData]
    let selectedIndex: Int
    let style: ChatAppearanceStyle
    let onSelectCommand: (CommandSuggestionViewData) -> Void
    let onSelectModel: (ModelSuggestionViewData) -> Void

    private var suggestionsMaxHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 320 : 240
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !modelSuggestions.isEmpty {
                    modelSuggestionSections
                } else {
                    commandSuggestionSections
                }
            }
        }
        .frame(maxHeight: suggestionsMaxHeight)
        .background(AppTheme.panel)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private var groupedCommands: [(category: String, commands: [IndexedCommand])] {
        let grouped = Dictionary(grouping: Array(commandSuggestions.enumerated())) { $0.element.sectionTitle }
        return grouped.keys.sorted().map { key in
            (category: key, commands: grouped[key]?.map { IndexedCommand(index: $0.offset, item: $0.element) } ?? [])
        }
    }

    private var groupedModels: [(category: String, models: [IndexedModel])] {
        let grouped = Dictionary(grouping: Array(modelSuggestions.enumerated())) { $0.element.sectionTitle }
        return grouped.keys.sorted().map { key in
            (category: key, models: grouped[key]?.map { IndexedModel(index: $0.offset, item: $0.element) } ?? [])
        }
    }

    private var commandSuggestionSections: some View {
        VStack(spacing: 0) {
            ForEach(Array(groupedCommands.enumerated()), id: \.offset) { sectionIndex, section in
                VStack(spacing: 0) {
                    HStack {
                        Text(section.category)
                            .font(style.suggestionSectionFont)
                            .foregroundStyle(AppTheme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, sectionIndex == 0 ? 10 : 14)
                    .padding(.bottom, 6)

                    ForEach(Array(section.commands.enumerated()), id: \.element.item.id) { rowIndex, row in
                        Button {
                            onSelectCommand(row.item)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "terminal")
                                    .foregroundStyle(row.index == selectedIndex ? AppTheme.blue : AppTheme.dim)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.item.title)
                                        .font(style.suggestionCommandTitleFont)
                                        .foregroundStyle(AppTheme.text)
                                    Text(row.item.subtitle)
                                        .font(style.suggestionSubtitleFont)
                                        .foregroundStyle(AppTheme.dim)
                                }
                                Spacer(minLength: 8)
                                if let hint = row.item.argumentsHint {
                                    Text(hint)
                                        .font(style.suggestionHintFont)
                                        .foregroundStyle(AppTheme.dim)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(row.index == selectedIndex ? AppTheme.blue.opacity(0.10) : Color.clear)
                        }
                        .buttonStyle(.plain)

                        if rowIndex < section.commands.count - 1 {
                            Divider().overlay(AppTheme.border.opacity(0.8))
                        }
                    }
                }

                if sectionIndex < groupedCommands.count - 1 {
                    Divider()
                        .overlay(AppTheme.border.opacity(0.9))
                        .padding(.top, 8)
                }
            }
        }
    }

    private var modelSuggestionSections: some View {
        VStack(spacing: 0) {
            ForEach(Array(groupedModels.enumerated()), id: \.offset) { sectionIndex, section in
                VStack(spacing: 0) {
                    HStack {
                        Text(section.category)
                            .font(style.suggestionSectionFont)
                            .foregroundStyle(AppTheme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, sectionIndex == 0 ? 10 : 14)
                    .padding(.bottom, 6)

                    ForEach(Array(section.models.enumerated()), id: \.element.item.id) { rowIndex, row in
                        Button {
                            onSelectModel(row.item)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(row.index == selectedIndex ? AppTheme.blue : AppTheme.dim)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.item.title)
                                        .font(style.suggestionModelTitleFont)
                                        .foregroundStyle(AppTheme.text)
                                    Text(row.item.subtitle)
                                        .font(style.suggestionSubtitleFont)
                                        .foregroundStyle(AppTheme.dim)
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(row.index == selectedIndex ? AppTheme.blue.opacity(0.10) : Color.clear)
                        }
                        .buttonStyle(.plain)

                        if rowIndex < section.models.count - 1 {
                            Divider().overlay(AppTheme.border.opacity(0.8))
                        }
                    }
                }

                if sectionIndex < groupedModels.count - 1 {
                    Divider()
                        .overlay(AppTheme.border.opacity(0.9))
                        .padding(.top, 8)
                }
            }
        }
    }
}

private struct IndexedCommand {
    let index: Int
    let item: CommandSuggestionViewData
}

private struct IndexedModel {
    let index: Int
    let item: ModelSuggestionViewData
}
