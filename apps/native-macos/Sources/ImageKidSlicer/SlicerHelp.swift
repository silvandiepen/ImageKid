import AppKit

/// One-line explanations for the menu commands.
///
/// macOS menu items can carry a tooltip — `NSMenuItem.toolTip` — but SwiftUI's
/// `Commands` offers no way to set one, so the live menu is annotated directly.
/// Keeping the text here rather than beside each `Button` means one place to
/// read when wondering what a command does, and one place a test can check is
/// complete.
enum SlicerHelp {
    /// Keyed by the exact menu title. Commands whose title flips with state
    /// appear under both spellings.
    static let byMenuTitle: [String: String] = [
        // File
        "Open Image…": "Open one or more images. Each is added to the filmstrip rather than replacing what is already open.",
        "Open Session…": "Reopen a saved .slicer session, restoring every image with its slices, guides and settings.",
        "Save Slices…": "Write one file per slice of this image into a folder you choose.",
        "Save Session…": "Save which images are open and everything drawn on them, to pick up later.",
        "Export All Images…": "Run every open image that has slices in one go, one subfolder per image.",
        "Close Image": "Close the current image. Asks first if it has unsaved slices.",
        "Export Options…": "Choose the format, size and naming every export uses.",

        // Edit
        "Copy Slice": "Copy the selected slice's pixels to the clipboard at full resolution.",
        "Paste Image": "Open the image currently on the clipboard.",
        "Duplicate Slice": "Copy the selected slice, offset so you can see it. Option-drag a slice to pull out a copy instead.",
        "Delete": "Remove the selected slice, or the selected guide.",

        // Slice — tools
        "Slice": "Draw, select, move and resize slice rectangles.",
        "Guides": "Drag cutting lines across the image for Auto Slice to cut along.",
        "Crop": "Pick one region and save it straight out as a single file.",

        // Slice — actions
        "Crop & Save…": "Write the crop region as one file at source resolution.",
        "Reset Crop": "Return the crop region to the whole image.",
        "Edit Slice…": "Open the selected slice's inspector: name, exact size, position and anchor.",
        "Suggest Guides": "Find the runs of background separating the tiles and drop a guide down the middle of each. Best on a grid.",
        "Detect Elements": "Put one slice around each separate thing in the image, wherever it sits. Best on a scattered layout.",
        "Auto Slice from Guides": "Cut the image into one slice per cell between the current guides and grid lines.",
        "Apply Layout to All Images": "Copy this image's slices and guides onto every other open image.",
        "Clear Guides": "Remove every guide. The slices they produced are left alone.",

        // Slice — locking
        "Lock Slice": "Make the selected slice inert: it cannot be moved, resized or deleted, and a drag over it draws a new slice.",
        "Unlock Slice": "Let the selected slice respond to the pointer again.",
        "Unlock All Slices": "Release every locked slice on this image.",

        // Slice — toggles
        "Snap to Guides and Slices": "Stick dragged edges to guides, the grid, and other slices' edges.",
        "Snap to Centre Lines": "Also stick to the middle of the image and of other slices.",
        "Snap to Content Edges": "Also stick to where the tiles in the image actually start and stop.",
        "Show Grid": "Draw a regular grid to snap and auto-slice against.",

        // View
        "Zoom In": "Enlarge the view. Slice geometry is unaffected.",
        "Zoom Out": "Shrink the view. Slice geometry is unaffected.",
        "Fit to Window": "Fit the whole image in the window again.",
        "Show Slices List": "Show the list beside the canvas, for renaming, locking and deleting.",
        "Hide Slices List": "Hide the slices list.",

        // Help
        "About Slicer": "Show the app version and shortcuts to the other ImageKid apps.",
        "Slicer Support": "Open ImageKid support in your web browser.",
        "Privacy Policy": "Read the ImageKid privacy policy in your web browser.",

        // Submenus
        "Templates": "Lay a ready-made grid of slices over the whole image."
    ]

    /// Every item in a Templates submenu means the same thing, and its title is
    /// the template's own name, so it cannot be listed above.
    static let templateItem = "Lay this grid of slices over the whole image, replacing the current ones."

    /// Annotate a live menu, and everything under it.
    ///
    /// Called each time a menu opens rather than once at launch: SwiftUI
    /// rebuilds these items as state changes, and a title that flips between
    /// Lock and Unlock would otherwise keep the tooltip it was born with.
    @MainActor
    static func applyTooltips(to menu: NSMenu, parentTitle: String? = nil) {
        for item in menu.items {
            if let text = byMenuTitle[item.title] {
                item.toolTip = text
            } else if parentTitle == "Templates" {
                item.toolTip = templateItem
            }
            if let submenu = item.submenu {
                applyTooltips(to: submenu, parentTitle: item.title)
            }
        }
    }
}
