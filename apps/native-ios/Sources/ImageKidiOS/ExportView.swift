import SwiftUI

/// Sheet for exporting the current working image: pick a format and quality,
/// then save to Photos or share.
struct ExportView: View {
    let image: CGImage

    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .png
    @State private var quality: Double = 0.9
    @State private var shareURL: URL?
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if format.supportsQuality {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quality \(Int(quality * 100))%")
                                .font(.subheadline)
                            Slider(value: $quality, in: 0.1...1)
                        }
                    }

                    if !format.preservesTransparency {
                        Text("This format flattens transparency onto white.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                            if isSaving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isSaving)

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { regenerateShareURL() }
            .onChange(of: format) { _, _ in regenerateShareURL() }
            .onChange(of: quality) { _, _ in regenerateShareURL() }
        }
    }

    private func regenerateShareURL() {
        shareURL = ImageExporter.writeTemporary(image, format: format, quality: CGFloat(quality))
    }

    private func save() {
        guard let url = ImageExporter.writeTemporary(image, format: format, quality: CGFloat(quality)) else {
            message = "Could not encode the image."
            return
        }
        isSaving = true
        message = nil
        Task {
            do {
                try await PhotoSaver.save(fileURL: url)
                message = "Saved to Photos."
            } catch {
                message = error.localizedDescription
            }
            isSaving = false
        }
    }
}
