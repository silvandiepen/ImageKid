import AppKit
import Foundation

struct BatchItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case processing(String, Double?)
        case done(URL)
        case failed(String)
    }

    let id = UUID()
    let sourceURL: URL
    var thumbnail: NSImage?
    var pixelSize: CGSize?
    var state: State = .waiting

    var fileName: String {
        sourceURL.lastPathComponent
    }

    var sizeLabel: String {
        guard let pixelSize else { return "Unknown size" }
        return "\(Int(pixelSize.width)) x \(Int(pixelSize.height)) px"
    }

    static func == (lhs: BatchItem, rhs: BatchItem) -> Bool {
        lhs.id == rhs.id
    }
}
