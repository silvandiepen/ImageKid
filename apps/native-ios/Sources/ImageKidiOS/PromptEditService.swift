import CoreGraphics
import Foundation
import UIKit

enum PromptEditError: LocalizedError {
    case missingCredential
    case imageEncodingFailed
    case timedOut
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Add your OpenAI API key first."
        case .imageEncodingFailed:
            return "The image could not be prepared for editing."
        case .timedOut:
            return "The edit timed out. Try again."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        }
    }
}

/// Prompted image editing through OpenAI's image edits endpoint, mirroring the
/// macOS app: user-supplied key, explicit action, no other network use.
struct OpenAIImageEditProvider {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
    private static let model = "gpt-image-1.5"

    func edit(_ image: CGImage, prompt: String) async throws -> CGImage {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw PromptEditError.missingCredential }
        guard let imageData = UIImage(cgImage: image).pngData() else {
            throw PromptEditError.imageEncodingFailed
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let boundary = "ImageKid-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            fields: [
                "model": Self.model,
                "prompt": trimmedPrompt,
                "size": "auto",
                "quality": "medium",
                "output_format": "png"
            ],
            fileFieldName: "image",
            fileName: "imagekid-source.png",
            fileData: imageData,
            boundary: boundary
        )

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 420
        let session = URLSession(configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw PromptEditError.timedOut
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw PromptEditError.apiError(Self.apiErrorMessage(from: data) ?? "OpenAI image editing failed.")
        }

        let decoded = try JSONDecoder().decode(ImagesResponse.self, from: data)
        guard
            let base64 = decoded.data?.first?.b64Json,
            let editedData = Data(base64Encoded: base64),
            let editedImage = UIImage(data: editedData)?.cgImage
        else {
            throw PromptEditError.invalidResponse
        }
        return editedImage
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
    }

    private static func multipartBody(
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: image/png\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private struct ImagesResponse: Decodable {
    let data: [ImageEntry]?
}

private struct ImageEntry: Decodable {
    let b64Json: String?
    enum CodingKeys: String, CodingKey { case b64Json = "b64_json" }
}

private struct ErrorResponse: Decodable {
    let error: ErrorBody
}

private struct ErrorBody: Decodable {
    let message: String
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
