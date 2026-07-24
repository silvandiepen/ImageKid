import AppKit
import SwiftUI

/// The Settings window's panes, so the app can open it on the right one.
enum SettingsTab: String, Hashable {
    case system
    case actions
    case appearance
    case background
    case enhance
    case magic
}

/// Which pane the Settings window should show when it next appears. The
/// Settings scene owns no model of its own, so this tiny router carries the
/// request across (set it, then open the window).
@MainActor
final class SettingsTabRouter: ObservableObject {
    static let shared = SettingsTabRouter()
    @Published var requested: SettingsTab?

    private init() {}
}

enum SettingsWindow {
    /// Open Settings, optionally on a specific pane.
    @MainActor
    static func open(_ tab: SettingsTab? = nil) {
        if let tab { SettingsTabRouter.shared.requested = tab }
        NSApp.activate(ignoringOtherApps: true)
        // The SwiftUI `Settings` scene has no public opener before macOS 14's
        // SettingsLink (a View, useless from a model): this is the action the
        // app menu item itself sends.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// A feature with an optional, downloadable "Best Quality" model behind it.
///
/// Both features work out of the box with a built-in engine; the on-device
/// Core ML model is a one-off download that does a visibly better job. The
/// app offers it the first time you use the feature without it — accept and
/// the download starts (Settings opens on its progress), decline and it never
/// asks again. Either way the thing you clicked still happens, right now,
/// with whatever engine is installed.
enum BestQualityFeature: String, Identifiable, CaseIterable {
    case backgroundRemoval
    case upscale

    var id: String { rawValue }

    var model: CoreMLModel {
        switch self {
        case .backgroundRemoval: .birefnet
        case .upscale: .realESRGAN
        }
    }

    var settingsTab: SettingsTab {
        switch self {
        case .backgroundRemoval: .background
        case .upscale: .enhance
        }
    }

    var title: String {
        switch self {
        case .backgroundRemoval: "Use Best Quality for backgrounds?"
        case .upscale: "Use Best Quality for enlarging?"
        }
    }

    var message: String {
        switch self {
        case .backgroundRemoval:
            "Best Quality is a \(model.approxSize) on-device model with a steadier hand for "
                + "fuzzy hair and tricky edges. ImageKid can download it now and use it from "
                + "then on — this cutout still happens right away with the built-in engine."
        case .upscale:
            "Best Quality is a \(model.approxSize) on-device model that invents real detail "
                + "instead of stretching pixels. ImageKid can download it now and use it from "
                + "then on — this resize still happens right away with the standard engine."
        }
    }

    /// The model is on disk, so there is nothing to offer.
    var isInstalled: Bool { model.isDownloaded }

    private var declineKey: String { "declinedBestQuality.\(rawValue)" }

    /// The user said no once; never ask again.
    var wasDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declineKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: declineKey) }
    }

    /// Accepting also switches the feature's engine preference over, so the
    /// model is used the moment it finishes downloading.
    func selectBestQualityEngine() {
        switch self {
        case .backgroundRemoval:
            UserDefaults.standard.set(
                BackgroundRemovalEngine.bestQuality.rawValue, forKey: "backgroundRemovalEngine")
        case .upscale:
            UserDefaults.standard.set(
                UpscaleEngine.bestQuality.rawValue, forKey: "upscaleEngine")
        }
    }
}
