import Foundation

/// A named column × row layout that fills the whole image with slices in one
/// action — the fast path for the sheets people cut over and over.
struct SliceTemplate: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var columns: Int
    var rows: Int

    init(id: UUID = UUID(), name: String, columns: Int, rows: Int) {
        self.id = id
        self.name = name
        self.columns = max(1, min(columns, SliceGrid.range.upperBound))
        self.rows = max(1, min(rows, SliceGrid.range.upperBound))
    }

    var sliceCount: Int { columns * rows }

    var detail: String { "\(columns) × \(rows)  ·  \(sliceCount) slices" }

    /// The cell rectangles this template lays over the whole image.
    var rects: [CGRect] {
        SliceAutoLayout.rects(
            verticalCuts: (1..<max(columns, 1)).map { CGFloat($0) / CGFloat(columns) },
            horizontalCuts: (1..<max(rows, 1)).map { CGFloat($0) / CGFloat(rows) }
        )
    }

    static let builtIns: [SliceTemplate] = [
        SliceTemplate(name: "Halves, side by side", columns: 2, rows: 1),
        SliceTemplate(name: "Halves, stacked", columns: 1, rows: 2),
        SliceTemplate(name: "Thirds", columns: 3, rows: 1),
        SliceTemplate(name: "Quarters", columns: 2, rows: 2),
        SliceTemplate(name: "Nine up", columns: 3, rows: 3),
        SliceTemplate(name: "Sixteen up", columns: 4, rows: 4),
        SliceTemplate(name: "Contact sheet", columns: 5, rows: 4)
    ]
}

/// Where the user's own templates live. Built-ins are code; anything the user
/// saves is JSON in preferences — Slicer still has no document format.
@MainActor
final class SliceTemplateStore: ObservableObject {
    @Published private(set) var custom: [SliceTemplate] = []

    private let defaultsKey = "slicer.customTemplates"
    private let store: UserDefaults

    init(store: UserDefaults = SlicerDefaults.store) {
        self.store = store
        load()
    }

    var all: [SliceTemplate] { SliceTemplate.builtIns + custom }

    func save(name: String, columns: Int, rows: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        custom.append(SliceTemplate(name: trimmed, columns: columns, rows: rows))
        persist()
    }

    func remove(_ template: SliceTemplate) {
        custom.removeAll { $0.id == template.id }
        persist()
    }

    private func load() {
        guard
            let data = store.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([SliceTemplate].self, from: data)
        else {
            return
        }
        custom = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        store.set(data, forKey: defaultsKey)
    }
}

/// The defaults store every persisted Slicer preference goes through:
/// `.standard` normally, a wiped per-run suite under the UI-test arguments so
/// a test never inherits (or damages) real preferences.
enum SlicerDefaults {
    private static let suiteName = "com.hakobs.imagekid.slicer.uitest"

    static let store: UserDefaults = {
        guard UITestMode.enabled, let suite = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }()
}
