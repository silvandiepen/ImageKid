import FekthorKit
import SwiftUI

/// The New Icon prompt: a name (pre-filled with the next free
/// "icon_untitled" in the target category) and a category picker, then
/// straight into the editor. Validation mirrors the engine's rules so
/// almost every Create succeeds on the first try.
struct NewIconSheet: View {
    @ObservedObject var session: WorkspaceSession
    var initialCategory: String
    /// Returns true when the icon was created (the sheet closes); false
    /// keeps it open so the user can fix the name.
    var onCreate: (String, String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var problem: String? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Icon").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { create() }
            Picker("Category", selection: $category) {
                Text("Uncategorized").tag("")
                ForEach(session.workspace?.categories ?? [], id: \.self) {
                    Text($0).tag($0)
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            category = initialCategory
            name = session.nextFreeIconName(in: initialCategory)
            nameFocused = true
        }
        .onChange(of: category) { old, new in
            // An untouched default name stays collision-free per category.
            if name.isEmpty || name == session.nextFreeIconName(in: old) {
                name = session.nextFreeIconName(in: new)
            }
            problem = nil
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        let stem = trimmedName
        guard !stem.isEmpty else { return }
        guard !stem.hasPrefix("."), !stem.contains("/"), !stem.contains("\\") else {
            problem = "Names cannot be hidden or contain slashes."
            return
        }
        let clash = (session.workspace?.entries ?? []).contains {
            $0.category == category && $0.name.lowercased() == stem.lowercased()
        }
        guard !clash else {
            problem = "\(stem).svg already exists in that category — pick another name."
            return
        }
        if onCreate(stem, category) {
            dismiss()
        } else {
            problem = "The icon could not be created."
        }
    }
}
