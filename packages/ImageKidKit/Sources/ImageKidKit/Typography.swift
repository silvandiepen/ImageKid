import CoreText
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

/// Figtree, bundled with the kit and registered at runtime so both apps get it
/// without an Info.plist entry each. It is a variable font, so one file covers
/// every weight.
///
/// Registration is process-wide and idempotent; call `Typography.register()`
/// once at launch. `Font.figtree(...)` falls back to the system font if the
/// resource is ever missing, so nothing renders blank.
public enum Typography {
    public static let familyName = "Figtree"

    private static var didRegister = false

    public static func register() {
        guard !didRegister else { return }
        didRegister = true

        guard let url = Bundle.module.url(forResource: "Figtree", withExtension: "ttf") else {
            assertionFailure("Figtree.ttf missing from ImageKidKit resources")
            return
        }

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered by another bundle is fine; anything else is not.
            let code = CFErrorGetCode(error?.takeUnretainedValue())
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                assertionFailure("Could not register Figtree: \(String(describing: error))")
            }
        }
    }

    /// True once the family is actually resolvable — used for the fallback.
    static var isAvailable: Bool {
        register()
        #if canImport(AppKit)
            return NSFontManager.shared.availableFontFamilies.contains(familyName)
        #else
            return true
        #endif
    }
}

extension Font {
    /// Figtree at a given size and weight, falling back to the system font.
    public static func figtree(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard Typography.isAvailable else { return .system(size: size, weight: weight) }
        return .custom(Typography.familyName, size: size).weight(weight)
    }
}
