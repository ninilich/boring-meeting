import Foundation

enum AudioSource: String, Codable {
    case microphone
    case system
}

struct TranscriptSegment: Codable {
    let text: String
    let startTime: Double
    let endTime: Double
    let source: AudioSource
    let avgLogprob: Double?
    let noSpeechProb: Double?
    let compressionRatio: Double?
}
