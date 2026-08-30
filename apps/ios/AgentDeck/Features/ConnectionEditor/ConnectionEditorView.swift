import SwiftUI

struct ConnectionEditorView: View {
    @State var viewModel: ConnectionEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("R2 Connection")
                            .font(AppTheme.font(.title, size: .medium))
                            .foregroundStyle(AppTheme.text)
                        Text("Update the R2 endpoint and credentials the app uses for discovery and messaging.")
                            .font(AppTheme.font(.body, size: .medium))
                            .foregroundStyle(AppTheme.dim)

                        if viewModel.showBucketChangedAlert || viewModel.pendingConfig != nil {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.yellow)
                                    .padding(.top, 1)
                                Text("Changing the bucket or credentials will erase all locally cached sessions, messages, and attachment files.")
                                    .font(AppTheme.font(.footnote, size: .medium))
                                    .foregroundStyle(AppTheme.yellow)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(AppTheme.panel)

                ConnectionFormSection(
                    config: $viewModel.draft,
                    fontSize: .medium,
                    errorMessage: viewModel.actualErrorMessage
                )

                ConnectionFileTransferSection(
                    config: $viewModel.draft,
                    importErrorMessage: $viewModel.importErrorMessage,
                    fontSize: .medium
                )

                Section {
                    Button {
                        Task {
                            await viewModel.verifyAndPrepareSave()
                            if viewModel.pendingConfig == nil, viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isWorking {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Test & Save")
                                    .font(AppTheme.font(.headline, size: .medium, weight: .semibold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.draft.isComplete || viewModel.isWorking)
                }
                .listRowBackground(AppTheme.panel)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("R2 Config")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase local data?", isPresented: $viewModel.showBucketChangedAlert, titleVisibility: .visible) {
            Button("Clear & Save", role: .destructive) {
                Task {
                    await viewModel.confirmDestructiveSave()
                    if viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingConfig = nil
            }
        } message: {
            Text("Changing the bucket or credentials will erase all locally cached sessions, messages, and attachment files. This cannot be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        ConnectionEditorView(viewModel: ConnectionEditorViewModel(environment: .makeDefault()))
    }
}
