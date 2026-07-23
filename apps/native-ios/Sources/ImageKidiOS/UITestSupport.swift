import SwiftUI
import UIKit

/// Launch-argument hooks for the XCUITest suite. `--uitest` wipes persisted
/// state (panel dock spots, settings) so every test starts from the same blank
/// slate; `--uitest-image` additionally opens a generated sample picture
/// straight into the editor, bypassing the photo picker (whose privacy sheet
/// UI tests cannot reliably drive).
enum UITestSupport {
    static var isActive: Bool {
        CommandLine.arguments.contains("--uitest") || wantsSampleImage
    }

    static var wantsSampleImage: Bool {
        CommandLine.arguments.contains("--uitest-image")
    }

    /// Fresh state: drop everything the app persisted (dock panel positions,
    /// minimized flags, canvas settings) and turn off UIKit animations so the
    /// tests never race a transition.
    static func prepareFreshState() {
        guard isActive else { return }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UIView.setAnimationsEnabled(false)
    }

    /// UIView animations are already off (`prepareFreshState`), but SwiftUI
    /// drives its own Core Animation transactions — run the window's layer
    /// clock fast so synthesized events never race a transition.
    static func accelerateAnimations() {
        guard isActive else { return }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.layer.speed = 100 }
        }
    }

    /// A small generated picture for the editor — no bundled asset and no
    /// photo-library round trip. Solid quadrants so edits are visible while
    /// debugging a failed test's screenshots.
    static func makeSampleImage() -> UIImage {
        let size = CGSize(width: 640, height: 480)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo, .systemYellow]
            let half = CGSize(width: size.width / 2, height: size.height / 2)
            for (index, color) in colors.enumerated() {
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(
                    x: CGFloat(index % 2) * half.width,
                    y: CGFloat(index / 2) * half.height,
                    width: half.width,
                    height: half.height
                ))
            }
        }
    }
}
