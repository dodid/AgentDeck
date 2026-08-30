import SwiftUI

struct ConnectionFormSection: View {
    @Binding var config: ConnectionConfig
    let fontSize: FontSizePreference
    var errorMessage: String? = nil

    var body: some View {
        Section {
            Text("Paste your R2 values directly here if you want to configure the connection manually.")
                .font(AppTheme.font(.caption, size: fontSize))
                .foregroundStyle(AppTheme.dim)

            TextField("Endpoint", text: $config.endpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTheme.font(.body, size: fontSize))
                .onChange(of: config.endpoint) { _, newValue in
                    extractBucketFromEndpoint(newValue)
                }
            TextField("Bucket", text: $config.bucket)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTheme.font(.body, size: fontSize))
            TextField("Access Key ID", text: $config.accessKeyID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTheme.font(.body, size: fontSize))
            TextField("Secret Access Key", text: $config.secretAccessKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTheme.font(.body, size: fontSize))
        } header: {
            Text("Connection")
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.font(.footnote, size: fontSize))
                    .foregroundStyle(AppTheme.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .listRowBackground(AppTheme.panel)
    }

    private func extractBucketFromEndpoint(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty else { return }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let bucketCandidate = parts.last else { return }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let withoutBucket = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .dropLast()
        components?.path = withoutBucket.isEmpty ? "" : "/" + withoutBucket.joined(separator: "/")
        components?.query = nil
        components?.fragment = nil

        guard let cleanURL = components?.url else { return }
        let cleanEndpoint = cleanURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        config.endpoint = cleanEndpoint
        if config.bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.bucket = bucketCandidate
        }
    }
}
