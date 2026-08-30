import SwiftUI
import UniformTypeIdentifiers

struct ConnectionFileTransferSection: View {
    @Binding var config: ConnectionConfig
    @Binding var importErrorMessage: String?
    let fontSize: FontSizePreference

    @State private var showingImporter = false

    var body: some View {
        Section("Config File") {
            Text("Or download the template, fill it in, and upload the config file here.")
                .font(AppTheme.font(.caption, size: fontSize))
                .foregroundStyle(AppTheme.dim)

            Button {
                shareTemplate()
            } label: {
                Label("Download config template", systemImage: "square.and.arrow.down")
                    .font(AppTheme.font(.body, size: fontSize))
            }
            .foregroundStyle(AppTheme.text)

            Button {
                showingImporter = true
            } label: {
                Label("Upload config file", systemImage: "square.and.arrow.up")
                    .font(AppTheme.font(.body, size: fontSize))
            }
            .foregroundStyle(AppTheme.text)
        }
        .listRowBackground(AppTheme.panel)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw ConnectionConfigTextFileError.unreadableTextFile
            }

            config = try ConnectionConfigTextFile.applying(text, to: config)
            importErrorMessage = nil
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shareTemplate() {
        do {
            let url = try ConnectionConfigTextFile.writeTemplateFile()
            presentShareSheet(for: url)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func presentShareSheet(for url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let presenter = root.presentedViewController ?? root
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}

enum ConnectionConfigTextFile {
    static func templateText() -> String {
        """
        # AgentDeck config template
        # Fill in the values after the = signs.

        endpoint=
        bucket=
        access_key_id=
        secret_access_key=
        """
    }

    static func writeTemplateFile() throws -> URL {
        let filename = "agentdeck-config-template.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try templateText().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func applying(_ text: String, to config: ConnectionConfig) throws -> ConnectionConfig {
        var parsed: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }

            let rawKey = line[..<separatorIndex]
            let rawValue = line[line.index(after: separatorIndex)...]
            let key = rawKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            parsed[key] = value
        }

        guard !parsed.isEmpty else {
            throw ConnectionConfigTextFileError.noSupportedKeys
        }

        var updated = config
        if let endpoint = parsed["endpoint"] { updated.endpoint = endpoint }
        if let bucket = parsed["bucket"] { updated.bucket = bucket }
        if let accessKeyID = parsed["access_key_id"] ?? parsed["accesskeyid"] { updated.accessKeyID = accessKeyID }
        if let secretAccessKey = parsed["secret_access_key"] ?? parsed["secretaccesskey"] { updated.secretAccessKey = secretAccessKey }
        updated.region = "auto"
        updated.forcePathStyle = true
        return updated
    }
}

enum ConnectionConfigTextFileError: LocalizedError {
    case noSupportedKeys
    case unreadableTextFile

    var errorDescription: String? {
        switch self {
        case .noSupportedKeys:
            return String(localized: "The file did not contain any supported R2 config keys.")
        case .unreadableTextFile:
            return String(localized: "The selected file could not be read as plain text.")
        }
    }
}
