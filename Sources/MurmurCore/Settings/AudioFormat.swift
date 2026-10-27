import Foundation

/// How a recording is kept after it has been transcribed.
public enum AudioFormat: String, CaseIterable, Identifiable, Sendable {
    /// AAC in an `.m4a` file: about a tenth of the size, plenty for speech.
    case m4a
    /// The recording as captured (16 kHz mono PCM in `.caf` or `.wav`): larger files, nothing re-encoded.
    case original

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .m4a: "M4A"
        case .original: "Original"
        }
    }

    public var detail: String {
        switch self {
        case .m4a: "Smaller files. Converted after transcribing."
        case .original: "Keeps the recording as captured. Larger files."
        }
    }
}
