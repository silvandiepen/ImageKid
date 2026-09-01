import SwiftUI
import UIKit

/// Launch-argument hooks for the XCUITest suite. `--uitest` wipes persisted
/// state (panel dock spots, settings) so every test starts from the same blank
/// slate; `--uitest-image` additionally opens a generated sample picture
/// straight into the editor, bypassing the photo picker (whose privacy sheet
/// UI tests cannot reliably drive).
enum UITestSupport {
    static var isActive: Bool {
        CommandLine.arguments.contains("--uitest") || wantsSampleImage || wantsDemoImage
    }

    static var wantsSampleImage: Bool {
        CommandLine.arguments.contains("--uitest-image")
    }

    /// `--demo-image` is the screenshot counterpart of `--uitest-image`: the
    /// same bypass of the photo picker, but opening a picture worth looking at
    /// rather than the flat quadrants a failing test is read against.
    static var wantsDemoImage: Bool {
        CommandLine.arguments.contains("--demo-image")
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

    /// A generated picture for demo and screenshot runs: a portrait sunset over
    /// three ridges. Nothing is bundled and nothing is read from the photo
    /// library, so the same run produces the same picture on every machine.
    static func makeDemoImage() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Sky: night blue at the top, burning down into a low sun.
            if let sky = CGGradient(
                colorsSpace: space,
                colors: [
                    UIColor(red: 0.09, green: 0.13, blue: 0.33, alpha: 1).cgColor,
                    UIColor(red: 0.36, green: 0.25, blue: 0.52, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.42, blue: 0.35, alpha: 1).cgColor,
                    UIColor(red: 0.98, green: 0.75, blue: 0.38, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 0.42, 0.68, 1]
            ) {
                cg.drawLinearGradient(
                    sky,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height * 0.74),
                    options: [.drawsAfterEndLocation])
            }

            // The sun, and the haze around it.
            let sun = CGPoint(x: size.width * 0.62, y: size.height * 0.56)
            if let glow = CGGradient(
                colorsSpace: space,
                colors: [
                    UIColor(red: 1, green: 0.93, blue: 0.72, alpha: 0.85).cgColor,
                    UIColor(red: 1, green: 0.82, blue: 0.45, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    glow,
                    startCenter: sun, startRadius: 0,
                    endCenter: sun, endRadius: size.width * 0.45,
                    options: [])
            }
            cg.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.80, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: sun.x - 92, y: sun.y - 92, width: 184, height: 184))

            // Three ridges, each lower and darker than the one behind it.
            let ridges: [(base: CGFloat, lift: CGFloat, colour: UIColor, peaks: [CGFloat])] = [
                (0.70, 0.14, UIColor(red: 0.44, green: 0.30, blue: 0.46, alpha: 1), [0.20, 0.95, 0.35, 0.75, 0.15, 0.60]),
                (0.80, 0.13, UIColor(red: 0.27, green: 0.18, blue: 0.34, alpha: 1), [0.70, 0.25, 0.90, 0.30, 0.80, 0.20]),
                (0.90, 0.10, UIColor(red: 0.12, green: 0.08, blue: 0.19, alpha: 1), [0.30, 0.60, 0.20, 0.85, 0.45, 0.95]),
            ]
            for ridge in ridges {
                let path = UIBezierPath()
                let baseY = size.height * ridge.base
                path.move(to: CGPoint(x: 0, y: size.height))
                for (index, peak) in ridge.peaks.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(ridge.peaks.count - 1)
                    path.addLine(to: CGPoint(x: x, y: baseY - size.height * ridge.lift * peak))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.close()
                ridge.colour.setFill()
                path.fill()
            }
        }
    }
}
