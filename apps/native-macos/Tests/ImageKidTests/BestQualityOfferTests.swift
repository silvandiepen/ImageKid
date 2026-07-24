import XCTest

@testable import ImageKid

/// The one-time Best Quality offer: what it remembers, and what accepting it
/// changes. (Whether the model is installed is a filesystem fact, so the
/// tests here cover the parts that are ours.)
final class BestQualityOfferTests: XCTestCase {
    private let keys = [
        "declinedBestQuality.backgroundRemoval", "declinedBestQuality.upscale",
        "backgroundRemovalEngine", "upscaleEngine",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = keys.reduce(into: [:]) { $0[$1] = UserDefaults.standard.object(forKey: $1) }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testEachFeatureOffersItsOwnModelAndSettingsPane() {
        XCTAssertEqual(BestQualityFeature.backgroundRemoval.model, .birefnet)
        XCTAssertEqual(BestQualityFeature.backgroundRemoval.settingsTab, .background)
        XCTAssertEqual(BestQualityFeature.upscale.model, .realESRGAN)
        XCTAssertEqual(BestQualityFeature.upscale.settingsTab, .enhance)
    }

    /// The download size belongs in the question — 179 MB is a real decision.
    func testMessageNamesTheDownloadSize() {
        for feature in BestQualityFeature.allCases {
            XCTAssertTrue(
                feature.message.contains(feature.model.approxSize),
                "\(feature.rawValue) should say how big the download is")
        }
    }

    func testDeclineIsRememberedPerFeature() {
        XCTAssertFalse(BestQualityFeature.backgroundRemoval.wasDeclined)
        XCTAssertFalse(BestQualityFeature.upscale.wasDeclined)

        BestQualityFeature.backgroundRemoval.wasDeclined = true

        XCTAssertTrue(BestQualityFeature.backgroundRemoval.wasDeclined)
        XCTAssertFalse(
            BestQualityFeature.upscale.wasDeclined,
            "declining one feature must not silence the other")
    }

    func testAcceptingSwitchesThatFeaturesEngineOver() {
        BestQualityFeature.backgroundRemoval.selectBestQualityEngine()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "backgroundRemovalEngine"),
            BackgroundRemovalEngine.bestQuality.rawValue)
        XCTAssertNil(
            UserDefaults.standard.string(forKey: "upscaleEngine"),
            "the background offer must not touch the upscale engine")

        BestQualityFeature.upscale.selectBestQualityEngine()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "upscaleEngine"),
            UpscaleEngine.bestQuality.rawValue)
    }

    /// Best Quality selected but not installed (still downloading, say) must
    /// resolve to the built-in engine — a cutout never dead-ends on a
    /// missing model.
    func testEngineFallsBackToBuiltInWhileTheModelIsMissing() throws {
        try XCTSkipIf(
            BackgroundRemovalService.isBestQualityRuntimeAvailable,
            "the BiRefNet model is installed on this machine")
        UserDefaults.standard.set(
            BackgroundRemovalEngine.bestQuality.rawValue, forKey: "backgroundRemovalEngine")
        XCTAssertEqual(BackgroundRemovalService.effectiveEngine, .builtIn)
    }

    /// The contract the callers rely on: the offer holds the work, and
    /// answering it — either way — still does what the user clicked.
    @MainActor
    func testOfferHoldsTheWorkUntilAnsweredAndOnlyAsksOnce() throws {
        try XCTSkipIf(
            BestQualityFeature.upscale.isInstalled,
            "the Real-ESRGAN model is installed on this machine")
        let model = AppModel()
        var runs = 0

        XCTAssertTrue(model.offerBestQuality(.upscale) { runs += 1 })
        XCTAssertEqual(model.bestQualityOffer, .upscale)
        XCTAssertEqual(runs, 0, "the work waits for the answer")

        model.declineBestQualityOffer()
        XCTAssertNil(model.bestQualityOffer)
        XCTAssertEqual(runs, 1, "declining still runs the work")
        XCTAssertTrue(BestQualityFeature.upscale.wasDeclined)

        // Asked and answered: the next resize goes straight through.
        XCTAssertFalse(model.offerBestQuality(.upscale) { runs += 1 })
        XCTAssertNil(model.bestQualityOffer)
    }

    func testEnginePreferenceIsHonouredWhenNothingIsWrong() {
        UserDefaults.standard.set(
            BackgroundRemovalEngine.builtIn.rawValue, forKey: "backgroundRemovalEngine")
        XCTAssertEqual(BackgroundRemovalService.effectiveEngine, .builtIn)
    }
}
