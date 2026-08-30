import SwiftUI

/// What a drag on the canvas does.
enum SlicerTool: String, CaseIterable, Identifiable {
    /// Draw, select, move, and resize slice rectangles.
    case slice
    /// Drag cutting lines across the image for Auto Slice to cut along.
    case guides
    /// One region, saved straight out as a single file.
    case crop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slice: "Slice"
        case .guides: "Guides"
        case .crop: "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .slice: "rectangle.dashed"
        case .guides: "ruler"
        case .crop: "crop"
        }
    }

    var help: String {
        switch self {
        case .slice: "Slice — drag to draw a region (S)"
        case .guides: "Guides — drag a cutting line across the image (G)"
        case .crop: "Crop — one region, saved straight out as a file (C)"
        }
    }
}

/// The floating tool bar, in the same idiom as ImageKid's and Fekthor's:
/// material capsule, square tool buttons, dividers between groups.
struct SlicerToolbar: View {
    @ObservedObject var model: SlicerDocumentModel

    /// The SF Symbols the toolbar draws. Named here so a test can prove every
    /// one of them actually resolves on the deployment target — a missing
    /// symbol renders as an empty button with no warning at all.
    enum Symbol {
        static let snapping = "dot.squareshape.split.2x2"
        static let grid = "grid"
        static let templates = "square.grid.3x3"
        static let autoSlice = "square.split.2x2"
        static let clearGuides = "eraser.line.dashed"
        static let lock = "lock"
        static let lockFilled = "lock.fill"
        static let unlocked = "lock.open"
        static let sidebar = "sidebar.right"
        static let crop = "crop"
        static let suggest = "wand.and.stars"

        static var all: [String] {
            SlicerTool.allCases.map(\.symbolName)
                + [snapping, grid, templates, autoSlice, clearGuides, lock, lockFilled, unlocked, sidebar, suggest]
        }
    }

    @State private var showGrid = false
    @State private var showTemplates = false
    @State private var newTemplateName = ""

    var body: some View {
        HStack(spacing: 7) {
            ForEach(SlicerTool.allCases) { tool in
                Button {
                    model.activeTool = tool
                    if tool == .crop { model.prepareCropIfNeeded() }
                } label: {
                    icon(tool.symbolName, selected: model.activeTool == tool)
                }
                .help(tool.help)
                .accessibilityLabel(tool.label)
                .accessibilityIdentifier("slicer.tool.\(tool.rawValue)")
            }

            divider

            Button {
                model.isSnappingEnabled.toggle()
            } label: {
                icon(Symbol.snapping, selected: model.isSnappingEnabled)
            }
            .help("Snap slices to guides, the grid, and other slices")
            .accessibilityLabel("Snapping")
            .accessibilityIdentifier("slicer.snap")

            gridButton

            divider

            templatesButton

            Button {
                model.suggestGuides()
            } label: {
                icon(Symbol.suggest, selected: false)
            }
            .disabled(!model.canSuggestGuides)
            .help("Suggest Guides — find the gutters between tiles")
            .accessibilityLabel("Suggest Guides")
            .accessibilityIdentifier("slicer.suggestGuides")

            Button {
                model.autoSlice()
            } label: {
                icon(Symbol.autoSlice, selected: false)
            }
            .disabled(!model.canAutoSlice)
            .help("Auto Slice — one slice per cell between the cutting lines")
            .accessibilityLabel("Auto Slice")
            .accessibilityIdentifier("slicer.autoSlice")

            Button {
                model.clearGuides()
            } label: {
                icon(Symbol.clearGuides, selected: false)
            }
            .disabled(model.guides.isEmpty)
            .help("Remove every guide")
            .accessibilityLabel("Clear Guides")
            .accessibilityIdentifier("slicer.clearGuides")

            divider

            Button {
                model.toggleLockOnSelection()
            } label: {
                icon(model.selectedSliceIsLocked ? "lock.fill" : Symbol.lock, selected: false)
            }
            .disabled(model.selectedSlice == nil)
            .help("Lock the selected slice so the pointer ignores it")
            .accessibilityLabel("Lock Slice")
            .accessibilityIdentifier("slicer.lock")

            Button {
                model.isSidebarVisible.toggle()
            } label: {
                icon(Symbol.sidebar, selected: model.isSidebarVisible)
            }
            .help("Show the slices list — rename, lock, and delete")
            .accessibilityLabel("Slices List")
            .accessibilityIdentifier("slicer.sidebarToggle")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { SlicerSurface.glass(RoundedRectangle(cornerRadius: 19, style: .continuous)) }
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(SlicerSurface.hairline)
        )
        .shadow(color: .black.opacity(0.4), radius: 26, y: 12)
    }

    // MARK: - Grid

    private var gridButton: some View {
        Button {
            showGrid.toggle()
        } label: {
            icon(Symbol.grid, selected: model.grid.isEnabled)
        }
        .help("Grid — a regular guide grid to snap and auto-slice against")
        .accessibilityLabel("Grid")
        .accessibilityIdentifier("slicer.grid")
        .popover(isPresented: $showGrid, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show grid", isOn: $model.grid.isEnabled)

                Stepper(value: $model.grid.columns, in: SliceGrid.range) {
                    Text("Columns: \(model.grid.columns)")
                }
                Stepper(value: $model.grid.rows, in: SliceGrid.range) {
                    Text("Rows: \(model.grid.rows)")
                }

                Toggle("Snap to centre lines", isOn: $model.snapsToCentreLines)

                Divider()

                HStack {
                    TextField("Template name", text: $newTemplateName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        model.saveCurrentGridAsTemplate(named: newTemplateName)
                        newTemplateName = ""
                    }
                    .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Saves this column × row grid as a reusable template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    // MARK: - Templates

    private var templatesButton: some View {
        Button {
            showTemplates.toggle()
        } label: {
            icon(Symbol.templates, selected: false)
        }
        .disabled(!model.hasSource)
        .help("Templates — lay a ready-made grid of slices over the image")
        .accessibilityLabel("Templates")
        .accessibilityIdentifier("slicer.templates")
        .popover(isPresented: $showTemplates, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SliceTemplate.builtIns) { template in
                    templateRow(template, removable: false)
                }

                if !model.templates.custom.isEmpty {
                    Divider().padding(.vertical, 6)
                    Text("Your templates")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    ForEach(model.templates.custom) { template in
                        templateRow(template, removable: true)
                    }
                }
            }
            .padding(8)
            .frame(width: 280)
        }
    }

    private func templateRow(_ template: SliceTemplate, removable: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                showTemplates = false
                model.apply(template)
            } label: {
                HStack(spacing: 10) {
                    TemplatePreview(columns: template.columns, rows: template.rows)
                        .frame(width: 30, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.name).font(.callout.weight(.medium))
                        Text(template.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("slicer.template.\(template.columns)x\(template.rows)")

            if removable {
                Button {
                    model.templates.remove(template)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete this template")
                .accessibilityLabel("Delete template \(template.name)")
                .padding(.trailing, 8)
            }
        }
    }

    // MARK: - Chrome

    private var divider: some View {
        Divider().frame(height: 30)
    }

    private func icon(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: selected ? .semibold : .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? Color.white : .primary)
            .frame(width: 40, height: 40)
            .background(
                selected ? Color.accentColor : Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The little column × row thumbnail next to a template's name.
private struct TemplatePreview: View {
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size = proxy.size
                path.addRect(CGRect(origin: .zero, size: size))
                for column in 1..<max(columns, 1) {
                    let x = size.width * CGFloat(column) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 1..<max(rows, 1) {
                    let y = size.height * CGFloat(row) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.accentColor, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
