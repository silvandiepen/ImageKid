import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

@MainActor
final class SlicerDocumentModelTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!

    override func setUpWithError() throws {
        // A throwaway defaults suite, so saving a template in a test never
        // touches the developer's real preferences.
        suiteName = "com.hakobs.imagekid.slicer.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
        // Slices belong to an image, so every test needs one open.
        try open(named: "sheet")
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    /// Open a generated image and make it current.
    @discardableResult
    private func open(named name: String, width: Int = 200, height: Int = 100) throws -> SlicerDocumentModel.ImageSession.ID {
        let image = try TestImages.halves(width: width, height: height)
        model.append(SlicerDocumentModel.Source(
            url: URL(fileURLWithPath: "/tmp/\(name).png"),
            displayName: name,
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            outputType: .png,
            fileExtension: "png"
        ))
        return try XCTUnwrap(model.currentImageID)
    }

    @discardableResult
    private func addSlice(_ rect: CGRect) -> Slice.ID {
        model.addSlice(rect)
        return model.slices.last!.id
    }

    // MARK: - Editing

    func testAddingASliceSelectsIt() {
        let id = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        XCTAssertEqual(model.selectedSliceID, id)
        XCTAssertEqual(model.slices.count, 1)
    }

    func testTooSmallASliceIsNotAdded() {
        model.addSlice(CGRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001))
        XCTAssertTrue(model.slices.isEmpty)
    }

    func testRenamingAndClearingTheNameRestoresTheAutomaticOne() {
        let id = addSlice(CGRect(x: 0, y: 0, width: 0.4, height: 0.4))
        model.rename(id: id, to: "hero")
        XCTAssertEqual(model.slices[0].name, "hero")
        XCTAssertEqual(model.slices[0].displayName(at: 0), "hero")

        model.rename(id: id, to: "   ")
        XCTAssertNil(model.slices[0].name)
        XCTAssertEqual(model.slices[0].displayName(at: 0), "Slice 1")
    }

    func testDeletingSelectsANeighbour() {
        addSlice(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))
        let second = addSlice(CGRect(x: 0.4, y: 0, width: 0.3, height: 0.3))
        let third = addSlice(CGRect(x: 0.7, y: 0, width: 0.3, height: 0.3))

        model.selectedSliceID = second
        model.deleteSelection()
        XCTAssertEqual(model.slices.count, 2)
        XCTAssertEqual(model.selectedSliceID, third)
    }

    // MARK: - Locking

    func testLockedSliceCannotBeMovedOrResized() {
        let id = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        model.setLocked(true, id: id)

        model.updateSlice(id: id, rect: CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4))
        XCTAssertEqual(model.slices[0].rect, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
    }

    func testLockedSliceCannotBeDeleted() {
        let id = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        model.setLocked(true, id: id)

        model.delete(id: id)
        XCTAssertEqual(model.slices.count, 1)
    }

    func testLockingClearsTheSelectionSoNoHandlesAreShown() {
        let id = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        XCTAssertEqual(model.selectedSliceID, id)

        model.setLocked(true, id: id)
        XCTAssertNil(model.selectedSliceID)
        XCTAssertTrue(model.hasLockedSlices)
    }

    func testUnlockAllReleasesEverySlice() {
        let first = addSlice(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))
        let second = addSlice(CGRect(x: 0.4, y: 0, width: 0.3, height: 0.3))
        model.setLocked(true, id: first)
        model.setLocked(true, id: second)

        model.unlockAllSlices()
        XCTAssertFalse(model.hasLockedSlices)
    }

    func testALayoutKeepsLockedSlicesAndReplacesTheRest() {
        let locked = addSlice(CGRect(x: 0, y: 0, width: 0.25, height: 0.25))
        addSlice(CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25))
        model.setLocked(true, id: locked)

        model.replaceSlices(with: SliceAutoLayout.rects(verticalCuts: [0.5], horizontalCuts: []))

        XCTAssertEqual(model.slices.count, 3, "the locked slice survives; the loose one does not")
        XCTAssertEqual(model.slices.filter(\.isLocked).map(\.id), [locked])
        XCTAssertEqual(model.selectedSliceID, model.slices[1].id, "selection lands on a slice that can be edited")
    }

    func testDuplicatingALockedSliceGivesAnEditableCopy() {
        let id = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        model.setLocked(true, id: id)
        model.selectedSliceID = id

        model.duplicateSelectedSlice()
        XCTAssertEqual(model.slices.count, 2)
        XCTAssertFalse(model.slices[1].isLocked)
    }

    // MARK: - Guides and cut lines

    func testAutoSliceNeedsAtLeastOneCutLine() {
        XCTAssertFalse(model.canAutoSlice, "with no source and no guides there is nothing to cut")

        model.addGuide(axis: .vertical, at: 0.5)
        XCTAssertEqual(model.cutLines.vertical, [0.5])
        XCTAssertTrue(model.cutLines.horizontal.isEmpty)
    }

    func testTheGridContributesCutLinesOnlyWhenShown() {
        model.grid = SliceGrid(isEnabled: false, columns: 2, rows: 2)
        XCTAssertTrue(model.cutLines.vertical.isEmpty)

        model.grid.isEnabled = true
        XCTAssertEqual(model.cutLines.vertical, [0.5])
        XCTAssertEqual(model.cutLines.horizontal, [0.5])
    }

    func testDeleteActsOnTheSelectedGuideBeforeTheSelectedSlice() {
        let slice = addSlice(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        model.addGuide(axis: .horizontal, at: 0.5)
        XCTAssertNil(model.selectedSliceID, "placing a guide takes the selection")

        model.deleteSelection()
        XCTAssertTrue(model.guides.isEmpty)
        XCTAssertEqual(model.slices.map(\.id), [slice], "the slice is untouched")
    }

    // MARK: - Templates

    func testSavedTemplatesPersistThroughTheStore() {
        model.grid = SliceGrid(isEnabled: true, columns: 5, rows: 2)
        model.saveCurrentGridAsTemplate(named: "Sprite row")

        XCTAssertEqual(model.templates.custom.map(\.name), ["Sprite row"])
        XCTAssertEqual(model.templates.custom.first?.columns, 5)
        XCTAssertEqual(model.templates.all.count, SliceTemplate.builtIns.count + 1)

        model.templates.remove(model.templates.custom[0])
        XCTAssertTrue(model.templates.custom.isEmpty)
    }

    func testABlankTemplateNameIsRejected() {
        model.saveCurrentGridAsTemplate(named: "   ")
        XCTAssertTrue(model.templates.custom.isEmpty)
    }
}


/// The filmstrip: several images open at once, each with its own layout.
@MainActor
final class SlicerMultipleImagesTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.multitests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    @discardableResult
    private func open(_ name: String, width: Int = 200, height: Int = 100) throws -> SlicerDocumentModel.ImageSession.ID {
        let image = try TestImages.halves(width: width, height: height)
        model.append(SlicerDocumentModel.Source(
            url: URL(fileURLWithPath: "/tmp/\(name).png"),
            displayName: name,
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            outputType: .png,
            fileExtension: "png"
        ))
        return try XCTUnwrap(model.currentImageID)
    }

    func testOpeningAddsToTheFilmstripRatherThanReplacing() throws {
        let first = try open("one")
        let second = try open("two")

        XCTAssertEqual(model.images.count, 2)
        XCTAssertTrue(model.hasMultipleImages)
        XCTAssertEqual(model.currentImageID, second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(model.source?.displayName, "two")
    }

    func testEachImageKeepsItsOwnSlicesAndView() throws {
        let first = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        model.setZoom(3)

        try open("two")
        XCTAssertTrue(model.slices.isEmpty, "a new image starts clean")
        XCTAssertEqual(model.zoom, 1, "and at its own fit-to-window zoom")

        model.select(imageID: first)
        XCTAssertEqual(model.slices.count, 1)
        XCTAssertEqual(model.zoom, 3)
    }

    func testApplyingTheLayoutCopiesSlicesAndGuidesToEveryOtherImage() throws {
        let first = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        model.addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        model.addGuide(axis: .vertical, at: 0.5)

        // A different shape entirely, to prove the normalised layout travels.
        try open("two", width: 900, height: 300)
        XCTAssertTrue(model.slices.isEmpty)

        model.select(imageID: first)
        model.applyLayoutToAllImages()

        let other = try XCTUnwrap(model.images.first { $0.id != first })
        XCTAssertEqual(other.slices.map(\.rect), model.slices.map(\.rect))
        XCTAssertEqual(other.guides.map(\.position), [0.5])
        XCTAssertTrue(other.hasUnsavedSlices)
    }

    func testApplyingTheLayoutKeepsLockedSlicesOnTheOtherImages() throws {
        let first = try open("one")
        try open("two")
        let lockedID = try XCTUnwrap({ () -> Slice.ID? in
            model.addSlice(CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
            return model.slices.last?.id
        }())
        model.setLocked(true, id: lockedID)

        model.select(imageID: first)
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        model.applyLayoutToAllImages()

        let other = try XCTUnwrap(model.images.first { $0.id != first })
        XCTAssertEqual(other.slices.count, 2, "the locked slice survives, the layout is added")
        XCTAssertTrue(other.slices[0].isLocked)
        XCTAssertFalse(other.slices[1].isLocked)
    }

    func testApplyingTheLayoutNeedsMoreThanOneImage() throws {
        try open("only")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        model.applyLayoutToAllImages()
        XCTAssertEqual(model.images.count, 1)
    }

    func testClosingSelectsANeighbour() throws {
        try open("one")
        let second = try open("two")
        let third = try open("three")

        model.select(imageID: second)
        model.close(imageID: second)

        XCTAssertEqual(model.images.count, 2)
        XCTAssertEqual(model.currentImageID, third, "the next image takes over")
    }

    func testClosingTheLastImageLeavesNothingCurrent() throws {
        let only = try open("only")
        model.close(imageID: only)
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertNil(model.currentImageID)
        XCTAssertNil(model.source)
        XCTAssertTrue(model.slices.isEmpty)
    }

    func testExportAllNeedsAtLeastOneImageWithSlices() throws {
        try open("one")
        try open("two")
        XCTAssertFalse(model.canExportAll)

        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertTrue(model.canExportAll)
    }

    func testUnsavedWorkIsCountedAcrossEveryImage() throws {
        let first = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.4, height: 0.4))
        try open("two")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.4, height: 0.4))

        XCTAssertEqual(model.imagesWithUnsavedSlices.count, 2)

        model.select(imageID: first)
        model.deleteSelection()
        XCTAssertEqual(model.imagesWithUnsavedSlices.count, 1)
    }

    func testAdoptReplacesEverySession() throws {
        try open("one")
        try open("two")

        let image = try TestImages.halves(width: 40, height: 40)
        model.adopt(SlicerDocumentModel.Source(
            url: nil,
            displayName: "fresh",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 40, height: 40)),
            outputType: .png,
            fileExtension: "png"
        ))

        XCTAssertEqual(model.images.count, 1)
        XCTAssertEqual(model.source?.displayName, "fresh")
    }

    func testDetectionResultsStayWithTheImageThatStartedDetection() throws {
        let first = try open("one")
        let second = try open("two")

        model.applySuggestedGuides(
            SliceDetection.Suggestion(vertical: [0.25], horizontal: [0.75]),
            to: first
        )
        model.applyDetectedElements(
            [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)],
            to: first
        )

        let origin = try XCTUnwrap(model.images.first { $0.id == first })
        let current = try XCTUnwrap(model.images.first { $0.id == second })
        XCTAssertEqual(origin.guides.map(\.position), [0.25, 0.75])
        XCTAssertEqual(origin.slices.count, 1)
        XCTAssertTrue(current.guides.isEmpty)
        XCTAssertTrue(current.slices.isEmpty)
    }

    func testExportCompletionMarksOnlyTheOriginatingUnchangedImageSaved() throws {
        let first = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let exportedSlices = model.slices

        let second = try open("two")
        model.addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        model.markSlicesSaved(imageID: first, matching: exportedSlices)

        XCTAssertFalse(try XCTUnwrap(model.images.first { $0.id == first }).hasUnsavedSlices)
        XCTAssertTrue(try XCTUnwrap(model.images.first { $0.id == second }).hasUnsavedSlices)
    }

    func testExportCompletionDoesNotMarkAnEditedOriginSaved() throws {
        let first = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let exportedSlices = model.slices
        model.addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        model.markSlicesSaved(imageID: first, matching: exportedSlices)

        XCTAssertTrue(try XCTUnwrap(model.images.first { $0.id == first }).hasUnsavedSlices)
    }

    func testSameNamedSourcesReceiveDistinctExportFolders() {
        XCTAssertEqual(
            SlicerDocumentModel.uniqueExportFolderNames(for: ["sheet", "sheet", "Sheet", "other"]),
            ["sheet", "sheet-2", "Sheet-3", "other"]
        )
    }
}

/// Which tool you are left holding after an action that produces geometry.
@MainActor
final class SlicerToolHandoffTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.handoff.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
        let image = try TestImages.halves(width: 200, height: 100)
        model.adopt(SlicerDocumentModel.Source(
            url: nil,
            displayName: "sheet",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 200, height: 100)),
            outputType: .png,
            fileExtension: "png"
        ))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    func testLayingSlicesDownReturnsToTheSliceTool() {
        model.activeTool = .guides
        model.replaceSlices(with: [CGRect(x: 0, y: 0, width: 0.5, height: 1)])
        XCTAssertEqual(model.activeTool, .slice, "otherwise the next click lays a guide over the new slices")
    }

    func testATemplateAlsoReturnsToTheSliceTool() {
        model.activeTool = .crop
        model.apply(SliceTemplate(name: "Quarters", columns: 2, rows: 2))
        XCTAssertEqual(model.activeTool, .slice)
        XCTAssertEqual(model.slices.count, 4)
    }

    func testAutoSliceAlsoReturnsToTheSliceTool() {
        model.activeTool = .guides
        model.addGuide(axis: .vertical, at: 0.5)
        model.autoSlice()
        XCTAssertEqual(model.activeTool, .slice)
        XCTAssertEqual(model.slices.count, 2)
    }
}

/// The filmstrip's order, which decoding finishing out of order must not
/// disturb.
@MainActor
final class SlicerFilmstripOrderTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.order.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    private func source(_ name: String) throws -> SlicerDocumentModel.Source {
        let image = try TestImages.halves(width: 40, height: 20)
        return SlicerDocumentModel.Source(
            url: URL(fileURLWithPath: "/tmp/\(name).png"),
            displayName: name,
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 40, height: 20)),
            outputType: .png,
            fileExtension: "png"
        )
    }

    func testImagesLandInTheOrderAskedForNotTheOrderTheyDecodeIn() throws {
        // Third finishes first, first finishes last — as detached decoding does.
        model.append(try source("third"), order: 2, selects: false)
        model.append(try source("second"), order: 1, selects: false)
        model.append(try source("first"), order: 0, selects: true)

        XCTAssertEqual(model.images.map(\.source.displayName), ["first", "second", "third"])
    }

    func testOpeningSeveralSelectsTheFirstWhicheverArrivesFirst() throws {
        model.append(try source("second"), order: 1, selects: false)
        model.append(try source("first"), order: 0, selects: true)

        XCTAssertEqual(model.source?.displayName, "first")
    }

    func testSomethingIsAlwaysSelectedEvenIfNothingClaimsIt() throws {
        model.append(try source("only"), order: 5, selects: false)
        XCTAssertEqual(model.source?.displayName, "only", "an unselected first image still becomes current")
    }

    func testOpeningOneMoreLaterSelectsIt() throws {
        model.append(try source("first"), order: 0, selects: true)
        model.append(try source("later"))

        XCTAssertEqual(model.source?.displayName, "later")
        XCTAssertEqual(model.images.map(\.source.displayName), ["first", "later"])
    }
}
