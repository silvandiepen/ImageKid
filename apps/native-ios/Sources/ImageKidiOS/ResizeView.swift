import ImageKidInference
import SwiftUI

/// Resize + upscale editor. Exact width/height with optional aspect lock and
/// percentage presets (reported via `onApply`), plus an Enlarge section that
/// mirrors the macOS app: engine (Standard / Best Quality), content mode, and a
/// 2× / 4× / 8× factor.
struct ResizeView: View {
    @ObservedObject var model: InferenceModel
    let pixelSize: CGSize
    let onApply: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width: Int
    @State private var height: Int
    @State private var lockAspect = true
    @State private var upscaleEngine: UpscaleEngineChoice = .standard
    @State private var contentMode: UpscaleContentMode = .automatic
    @State private var upscaleFactor: CGFloat = 2

    private let aspect: CGFloat

    private static let engineKey = "imagekid.upscale.engine"
    private static let factorKey = "imagekid.upscale.factor"

    init(model: InferenceModel, pixelSize: CGSize, onApply: @escaping (Int, Int) -> Void) {
        self.model = model
        self.pixelSize = pixelSize
        self.onApply = onApply
        _width = State(initialValue: max(1, Int(pixelSize.width.rounded())))
        _height = State(initialValue: max(1, Int(pixelSize.height.rounded())))
        aspect = pixelSize.width / max(pixelSize.height, 1)

        // Preselect the last-used speed and amount.
        let defaults = UserDefaults.standard
        let savedEngine = defaults.string(forKey: Self.engineKey)
            .flatMap(UpscaleEngineChoice.init(rawValue:)) ?? .standard
        _upscaleEngine = State(initialValue: savedEngine)
        if let savedFactor = defaults.object(forKey: Self.factorKey) as? Double {
            _upscaleFactor = State(initialValue: CGFloat(savedFactor))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dimensions") {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: $width, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onChange(of: width) { _, newValue in
                                if lockAspect {
                                    height = max(1, Int((CGFloat(newValue) / aspect).rounded()))
                                }
                            }
                        Text("px").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: $height, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(lockAspect)
                            .foregroundStyle(lockAspect ? .secondary : .primary)
                        Text("px").foregroundStyle(.secondary)
                    }
                    Toggle("Lock aspect ratio", isOn: $lockAspect)
                        .onChange(of: lockAspect) { _, locked in
                            if locked { height = max(1, Int((CGFloat(width) / aspect).rounded())) }
                        }
                    Button("Apply Resize") { onApply(max(1, width), max(1, height)); dismiss() }
                }

                Section("Scale") {
                    HStack(spacing: 8) {
                        ForEach([25, 50, 75, 200], id: \.self) { percent in
                            Button("\(percent)%") { applyPercent(percent) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("Enlarge") {
                    Picker("Speed", selection: $upscaleEngine) {
                        ForEach(UpscaleEngineChoice.allCases) { Text($0.speedLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(upscaleEngine == .bestQuality
                         ? "Slow — best quality (AI model)."
                         : "Fast — quick Core Image enlarge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if upscaleEngine == .standard {
                        Picker("Content", selection: $contentMode) {
                            ForEach(UpscaleContentMode.allCases) { Text($0.label).tag($0) }
                        }
                    }

                    Picker("Amount", selection: $upscaleFactor) {
                        Text("2×").tag(CGFloat(2))
                        Text("4×").tag(CGFloat(4))
                        Text("8×").tag(CGFloat(8))
                    }
                    .pickerStyle(.segmented)

                    let out = CGSize(width: pixelSize.width * upscaleFactor, height: pixelSize.height * upscaleFactor)
                    Text("→ \(Int(out.width.rounded())) × \(Int(out.height.rounded())) px")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if upscaleEngine == .bestQuality, !model.downloader.isDownloaded(.realESRGAN) {
                        ModelDownloadRow(model: model, downloadable: .realESRGAN)
                    } else {
                        Button("Apply Upscale") {
                            UserDefaults.standard.set(upscaleEngine.rawValue, forKey: Self.engineKey)
                            UserDefaults.standard.set(Double(upscaleFactor), forKey: Self.factorKey)
                            model.upscale(scale: upscaleFactor, engine: upscaleEngine, contentMode: contentMode)
                            dismiss()
                        }
                    }
                }

                Section {
                    Text("Original \(Int(pixelSize.width.rounded())) × \(Int(pixelSize.height.rounded())) px")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Resize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func applyPercent(_ percent: Int) {
        let factor = CGFloat(percent) / 100
        width = max(1, Int((pixelSize.width * factor).rounded()))
        height = max(1, Int((pixelSize.height * factor).rounded()))
    }
}
