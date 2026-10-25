import Foundation
import MurmurCore
import WhisperKit

/// Downloads a Whisper model from Hugging Face (the model download is the only network use
/// besides StoreKit).
public struct WhisperKitDownloader: SpeechModelDownloader {
    private let downloadBase: URL

    public init(downloadBase: URL) {
        self.downloadBase = downloadBase
    }

    public func download(
        _ model: SpeechModel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        return try await WhisperKit.download(
            variant: model.variant,
            downloadBase: downloadBase,
            progressCallback: { progress in
                onProgress(progress.fractionCompleted)
            }
        )
    }
}
