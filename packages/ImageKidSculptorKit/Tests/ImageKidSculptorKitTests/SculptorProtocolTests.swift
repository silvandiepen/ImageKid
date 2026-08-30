import XCTest

@testable import ImageKidSculptorKit

/// These decode byte-for-byte copies of what `tools/sculptor-engine` emits. If
/// the Python side changes a key, these fail — which is the point: the protocol
/// is the contract between the two halves.
final class SculptorProtocolTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> WorkerMessage? {
        try WorkerMessage.decode(Data(json.utf8), using: decoder)
    }

    func testDecodesReady() throws {
        let message = try decode(
            #"{"type":"ready","protocolVersion":1,"engine":"triposr","engineAvailable":true,"detail":null}"#
        )
        guard case .ready(let ready) = message else { return XCTFail("expected ready") }
        XCTAssertEqual(ready.protocolVersion, 1)
        XCTAssertEqual(ready.engine, "triposr")
        XCTAssertTrue(ready.engineAvailable)
        XCTAssertNil(ready.detail)
    }

    func testDecodesUnavailableEngineWithDetail() throws {
        let message = try decode(
            #"{"type":"ready","protocolVersion":1,"engine":"triposr","engineAvailable":false,"detail":"TripoSR v1 is not installed."}"#
        )
        guard case .ready(let ready) = message else { return XCTFail("expected ready") }
        XCTAssertFalse(ready.engineAvailable)
        XCTAssertEqual(ready.detail, "TripoSR v1 is not installed.")
    }

    func testDecodesProgress() throws {
        let message = try decode(
            #"{"type":"progress","jobId":"j1","stage":"buildingHiddenSides","stageFraction":0.5,"fraction":0.75}"#
        )
        guard case .progress(let progress) = message else {
            return XCTFail("expected progress")
        }
        XCTAssertEqual(progress.jobId, "j1")
        XCTAssertEqual(progress.stage, .buildingHiddenSides)
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
    }

    func testDecodesEveryStage() throws {
        // The worker walks all six; none may fail to decode mid-generation.
        for stage in SculptorStage.allCases {
            let json = """
            {"type":"progress","jobId":"j","stage":"\(stage.rawValue)",\
            "stageFraction":0,"fraction":0}
            """
            guard case .progress(let progress) = try decode(json) else {
                return XCTFail("expected progress for \(stage)")
            }
            XCTAssertEqual(progress.stage, stage)
        }
    }

    func testDecodesResult() throws {
        // One line, exactly as the worker writes it.
        let json = #"{"type":"result","jobId":"j1","glbPath":"/w/output/model.glb","previewPath":"/w/output/preview.ply","exports":{"obj":"/w/output/model.obj"},"preparedImagePath":"/w/input/prepared.png","triangleCount":200864,"vertexCount":100480,"hasTexture":true,"appliedScale":1.0588,"boundingBoxLongestEdge":1.0,"upAxis":"+Y","originConvention":"bottomCentre","durationSeconds":14.913}"#
        let message = try decode(json)
        guard case .result(let result) = message else { return XCTFail("expected result") }
        XCTAssertEqual(result.glbPath, "/w/output/model.glb")
        XCTAssertEqual(result.previewPath, "/w/output/preview.ply")
        XCTAssertEqual(result.exports["obj"], "/w/output/model.obj")
        XCTAssertEqual(result.triangleCount, 200_864)
        XCTAssertTrue(result.hasTexture)
        XCTAssertEqual(result.upAxis, "+Y")
        XCTAssertEqual(result.originConvention, "bottomCentre")
    }

    func testDecodesRecoverableError() throws {
        let message = try decode(
            #"{"type":"error","jobId":"j1","code":"modelNotInstalled","message":"not installed","recoverable":true}"#
        )
        guard case .failure(let failure) = message else { return XCTFail("expected error") }
        XCTAssertEqual(failure.code, .modelNotInstalled)
        XCTAssertTrue(failure.recoverable)
    }

    func testDecodesErrorWithoutJobId() throws {
        // A malformed request is rejected before any job exists.
        let message = try decode(
            #"{"type":"error","jobId":null,"code":"malformedRequest","message":"bad","recoverable":false}"#
        )
        guard case .failure(let failure) = message else { return XCTFail("expected error") }
        XCTAssertNil(failure.jobId)
        XCTAssertFalse(failure.recoverable)
    }

    func testIgnoresUnknownMessageTypes() throws {
        // A newer worker must degrade rather than kill an older app.
        XCTAssertNil(try decode(#"{"type":"somethingNew","value":1}"#))
    }

    func testEncodesGenerateRequestWithTheKeysTheWorkerExpects() throws {
        let request = GenerateRequest(
            jobId: "j1",
            sourcePath: "/tmp/a.png",
            workspace: "/tmp/work",
            options: SculptorOptions(inputSize: 512, lowMemory: true)
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "generate")
        XCTAssertEqual(object["jobId"] as? String, "j1")
        XCTAssertEqual(object["sourcePath"] as? String, "/tmp/a.png")
        XCTAssertEqual(object["workspace"] as? String, "/tmp/work")

        let options = try XCTUnwrap(object["options"] as? [String: Any])
        XCTAssertEqual(options["inputSize"] as? Int, 512)
        XCTAssertEqual(options["lowMemory"] as? Bool, true)
        // Unset options must be omitted, not sent as null: the worker rejects
        // unknown or malformed option values rather than ignoring them.
        XCTAssertNil(options["seed"])
        XCTAssertNil(options["device"])
    }

    func testViewpointsCarryCameraElevationOnly() {
        // These are elevations, not total corrections: the engine's own
        // Z-up-to-Y-up convention is fixed inside the engine. Eye level must
        // therefore be a no-op, and the isometric Tiko renders measured ~30.
        XCTAssertEqual(SourceViewpoint.eyeLevel.pitchCorrection, 0)
        XCTAssertEqual(SourceViewpoint.raised.pitchCorrection, 15)
        XCTAssertEqual(SourceViewpoint.overhead.pitchCorrection, 30)
    }

    func testViewpointCorrectionsIncreaseWithCameraHeight() {
        let corrections = SourceViewpoint.allCases.map(\.pitchCorrection)
        XCTAssertEqual(corrections, corrections.sorted())
        for viewpoint in SourceViewpoint.allCases {
            XCTAssertFalse(viewpoint.title.isEmpty)
            XCTAssertFalse(viewpoint.detail.isEmpty)
        }
    }

    func testPitchCorrectionIsSentToTheWorker() throws {
        let request = GenerateRequest(
            jobId: "j1",
            sourcePath: "/tmp/a.png",
            workspace: "/tmp/w",
            options: SculptorOptions(
                pitchCorrection: SourceViewpoint.overhead.pitchCorrection
            )
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let options = try XCTUnwrap(object["options"] as? [String: Any])
        XCTAssertEqual(options["pitchCorrection"] as? Double, 30)
    }

    func testStageTitlesDescribeTheWaitNotTheEngine() {
        XCTAssertEqual(SculptorStage.reconstructing.title, "Reconstructing 3D")
        XCTAssertEqual(SculptorStage.buildingHiddenSides.title, "Building hidden sides")
        for stage in SculptorStage.allCases {
            XCTAssertFalse(stage.title.isEmpty)
        }
    }
}
