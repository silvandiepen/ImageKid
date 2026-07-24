import ImageKidKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    /// The app-wide downloader: a download started by a Best Quality offer
    /// has to show its progress here.
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @ObservedObject private var tabRouter = SettingsTabRouter.shared
    @State private var tab: SettingsTab = .system
    @State private var openAIKey = ""
    @State private var openAIKeyStatus: String?
    @State private var quickActions: [QuickActionDefinition] = []

    var body: some View {
        TabView(selection: $tab) {
            systemPane
                .tabItem {
                    Label("System", systemImage: "macwindow")
                }
                .tag(SettingsTab.system)

            quickActionsPane
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
                .tag(SettingsTab.actions)

            appearancePane
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }
            .tag(SettingsTab.appearance)

            backgroundRemovalPane
                .tabItem {
                    Label("Background", systemImage: "eraser")
                }
                .tag(SettingsTab.background)

            enhancePane
                .tabItem {
                    Label("Enhance", systemImage: "wand.and.stars")
                }
                .tag(SettingsTab.enhance)

            magicPane
                .tabItem {
                    Label("Magic", systemImage: "sparkles")
                }
                .tag(SettingsTab.magic)
        }
        .frame(width: 540, height: 380)
        .onAppear {
            openAIKey = KeychainStore.string(for: "openai-api-key") ?? ""
            quickActions = settings.quickActions
            showRequestedTab()
        }
        // Opened by a Best Quality offer: land on the pane with that
        // model's download on it (the window may already be open).
        .onChange(of: tabRouter.requested) { showRequestedTab() }
    }

    private func showRequestedTab() {
        guard let requested = tabRouter.requested else { return }
        tab = requested
        tabRouter.requested = nil
    }

    private var systemPane: some View {
        Form {
            Toggle("Show ImageKid in Finder context menus", isOn: contextMenuBinding)

            VStack(alignment: .leading, spacing: 6) {
                Text("Finder quick actions")
                    .font(.headline)
                Text("When bundled integration is added, ImageKid can appear when right-clicking image files with Upscale 2x, Upscale 4x, and Remove Background actions.")
                    .foregroundStyle(.secondary)
            }

            Text("The current Swift package build stores this preference, but Finder menu registration still requires the signed app bundle or extension target.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var quickActionsPane: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Actions")
                    .font(.headline)
                Text("Default and custom actions can be enabled for the future Finder context menu and can run multiple steps in order.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Create Action") {
                    quickActions.append(QuickActionDefaults.customDefinition())
                    saveQuickActions()
                }
                Button("Reset Defaults") {
                    quickActions = QuickActionDefaults.definitions
                    saveQuickActions()
                }
                Spacer()
            }

            ForEach($quickActions) { $action in
                quickActionEditor(action: $action)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func quickActionEditor(action: Binding<QuickActionDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("", isOn: action.isEnabled)
                    .labelsHidden()
                    .onChange(of: action.wrappedValue.isEnabled) { _, _ in saveQuickActions() }
                TextField("Name", text: action.title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveQuickActions() }
                if QuickActionDefaults.isDefault(id: action.wrappedValue.id) {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Delete", role: .destructive) {
                        quickActions.removeAll { $0.id == action.wrappedValue.id }
                        saveQuickActions()
                    }
                }
            }

            ForEach(action.steps.wrappedValue.indices, id: \.self) { index in
                quickActionStepEditor(action: action, index: index)
            }

            Menu("Add Step") {
                Button("Remove Background") {
                    action.wrappedValue.steps.append(.removeBackground)
                    saveQuickActions()
                }
                Button("Upscale 2x") {
                    action.wrappedValue.steps.append(.upscale(scale: 2))
                    saveQuickActions()
                }
                Button("Upscale 4x") {
                    action.wrappedValue.steps.append(.upscale(scale: 4))
                    saveQuickActions()
                }
                Button("Canvas 1024 x 1024") {
                    action.wrappedValue.steps.append(.canvas(width: 1024, height: 1024))
                    saveQuickActions()
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func quickActionStepEditor(action: Binding<QuickActionDefinition>, index: Int) -> some View {
        HStack {
            Text(action.wrappedValue.steps[index].label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            if case .canvas(let width, let height) = action.wrappedValue.steps[index] {
                TextField(
                    "Width",
                    value: Binding(
                        get: { width },
                        set: { newValue in
                            action.wrappedValue.steps[index] = .canvas(width: max(1, newValue), height: height)
                            saveQuickActions()
                        }
                    ),
                    format: .number
                )
                .frame(width: 72)
                Text("x")
                    .foregroundStyle(.secondary)
                TextField(
                    "Height",
                    value: Binding(
                        get: { height },
                        set: { newValue in
                            action.wrappedValue.steps[index] = .canvas(width: width, height: max(1, newValue))
                            saveQuickActions()
                        }
                    ),
                    format: .number
                )
                .frame(width: 72)
            }

            Button {
                action.wrappedValue.steps.remove(at: index)
                saveQuickActions()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(action.wrappedValue.steps.count <= 1)
        }
    }

    private var appearancePane: some View {
        Form {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Section("Canvas background") {
                // The shared control — identical to Fekthor's Settings.
                CanvasBackgroundControls(background: canvasBackgroundBinding)
            }

            LabeledContent("Image corner radius") {
                HStack {
                    Slider(value: imageCornerRadiusBinding, in: 0...32, step: 1)
                        .frame(width: 190)
                    Text("\(Int(settings.imageCornerRadius.rounded())) px")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var backgroundRemovalPane: some View {
        Form {
            Picker("Engine", selection: backgroundEngineBinding) {
                ForEach(BackgroundRemovalEngine.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in")
                    .font(.headline)
                Text("Quick and tidy for simple cutouts.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best Quality")
                            .font(.headline)
                        Text("A steadier hand for fuzzy hair, tricky edges, and busier pictures. On-device Core ML — no Python runtime.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(CoreMLModel.birefnet.approxSize)
                        .foregroundStyle(.secondary)
                }

                modelDownloadRow(.birefnet)

                Text("Optional download. Once it's on your Mac, everything happens on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    /// Download / progress / remove control for an optional Core ML model.
    @ViewBuilder
    private func modelDownloadRow(_ model: CoreMLModel) -> some View {
        HStack(spacing: 12) {
            switch modelDownloader.state(model) {
            case .ready:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Remove", role: .destructive) { modelDownloader.remove(model) }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 150)
                Spacer()
                Text("\(Int(fraction * 100))%").foregroundStyle(.secondary).monospacedDigit()
            case .failed(let message):
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                Spacer()
                Button("Retry") { modelDownloader.download(model) }
            case .notDownloaded:
                Label("Not downloaded", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") { modelDownloader.download(model) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var enhancePane: some View {
        Form {
            Section {
                Text("Enhance improves detail — and can enlarge — right on your Mac. Quick is built in. Higher grades use an on-device AI model you download once.")
                    .foregroundStyle(.secondary)
            }

            Section("Quality grades") {
                enhanceGradeRow(
                    title: "Quick",
                    detail: "Instant, built-in sharpening. No download.",
                    model: nil
                )
                enhanceGradeRow(
                    title: "High",
                    detail: "Sharper AI detail.",
                    model: .realESRGAN
                )
                enhanceGradeRow(
                    title: "Max",
                    detail: "Richest, most realistic detail.",
                    model: .auraSR
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    @ViewBuilder
    private func enhanceGradeRow(title: String, detail: String, model: CoreMLModel?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let model {
                    Text(model.approxSize)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Built in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let model {
                modelDownloadRow(model)
            }
        }
    }

    private var magicPane: some View {
        Form {
            Section("Magic") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe an edit and ImageKid sends the current rendered image to the configured provider, then replaces the workspace image with the result.")
                        .foregroundStyle(.secondary)

                    Text("Core tools remain local and do not need a provider key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Providers") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI")
                        .font(.headline)

                    SecureField("API key", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("The key is stored in your Mac keychain and is only used when you choose Magic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Save Key") {
                        saveOpenAIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove Key", role: .destructive) {
                        removeOpenAIKey()
                    }

                    Spacer()
                }

                if let openAIKeyStatus {
                    Text(openAIKeyStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { settings.appearanceMode },
            set: { settings.appearanceMode = $0 }
        )
    }

    private var canvasBackgroundBinding: Binding<CanvasBackground> {
        Binding(
            get: { settings.canvasBackground },
            set: { settings.canvasBackground = $0 }
        )
    }

    private var imageCornerRadiusBinding: Binding<Double> {
        Binding(
            get: { settings.imageCornerRadius },
            set: { settings.imageCornerRadius = $0 }
        )
    }

    private var backgroundEngineBinding: Binding<BackgroundRemovalEngine> {
        Binding(
            get: { settings.backgroundRemovalEngine },
            set: { settings.backgroundRemovalEngine = $0 }
        )
    }

    private var contextMenuBinding: Binding<Bool> {
        Binding(
            get: { settings.showInFinderContextMenus },
            set: { settings.showInFinderContextMenus = $0 }
        )
    }

    private func saveOpenAIKey() {
        do {
            try KeychainStore.set(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "openai-api-key")
            openAIKeyStatus = "Saved."
        } catch {
            openAIKeyStatus = error.localizedDescription
        }
    }

    private func removeOpenAIKey() {
        do {
            try KeychainStore.remove(account: "openai-api-key")
            openAIKey = ""
            openAIKeyStatus = "Removed."
        } catch {
            openAIKeyStatus = error.localizedDescription
        }
    }

    private func saveQuickActions() {
        settings.quickActions = quickActions
    }
}

// `CheckerboardBackground` now lives in ImageKidKit (shared with Fekthor).
