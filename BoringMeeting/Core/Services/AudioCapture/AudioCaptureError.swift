import Foundation

/// Errors that can occur during audio capture
enum AudioCaptureError: LocalizedError {
    
    // MARK: - Permission Errors
    
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    
    // MARK: - Device Errors
    
    case noMicrophoneFound
    case noDisplayFound
    case microphoneDisconnected
    case invalidAudioFormat
    
    // MARK: - Configuration Errors
    
    case audioEngineStartFailed(String)
    case streamCreationFailed(String)
    case formatConversionFailed
    
    // MARK: - File Errors
    
    case fileCreationFailed(String)
    case diskFull
    case writeError(String)
    
    // MARK: - System Errors
    
    case systemAudioCaptureFailed(String)
    case microphoneCaptureFailed(String)
    case alreadyRecording
    case notRecording
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        // Permissions
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission required.\n\nEnable in:\nSystem Settings > Privacy & Security > Screen Recording\n\nThen restart the app."
            
        case .microphonePermissionDenied:
            return "Microphone permission required.\n\nEnable in:\nSystem Settings > Privacy & Security > Microphone\n\nThen restart the app."
            
        // Devices
        case .noMicrophoneFound:
            return "No microphone found.\n\nPlease connect a microphone or check your audio settings."
            
        case .noDisplayFound:
            return "No display found for screen recording.\n\nThis is unusual - please restart the app."
            
        case .microphoneDisconnected:
            return "Microphone was disconnected during recording.\n\nPlease reconnect and try again."
            
        case .invalidAudioFormat:
            return "Invalid audio format configuration.\n\nPlease restart the app."
            
        // Configuration
        case .audioEngineStartFailed(let details):
            return "Failed to start audio engine.\n\nDetails: \(details)"
            
        case .streamCreationFailed(let details):
            return "Failed to create screen capture stream.\n\nDetails: \(details)"
            
        case .formatConversionFailed:
            return "Audio format conversion failed.\n\nThis may be due to incompatible audio settings."
            
        // File
        case .fileCreationFailed(let details):
            return "Failed to create recording file.\n\nDetails: \(details)"
            
        case .diskFull:
            return "Not enough disk space to save recording.\n\nPlease free up space and try again."
            
        case .writeError(let details):
            return "Failed to write audio data.\n\nDetails: \(details)"
            
        // System
        case .systemAudioCaptureFailed(let details):
            return "Failed to capture system audio.\n\nDetails: \(details)\n\nMake sure Screen Recording permission is granted."
            
        case .microphoneCaptureFailed(let details):
            return "Failed to capture microphone audio.\n\nDetails: \(details)\n\nMake sure Microphone permission is granted."
            
        case .alreadyRecording:
            return "Recording already in progress.\n\nStop the current recording first."
            
        case .notRecording:
            return "No recording in progress.\n\nStart a recording first."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied, .microphonePermissionDenied:
            return "Open System Settings and grant the required permission."
            
        case .noMicrophoneFound:
            return "Connect a microphone and try again."
            
        case .diskFull:
            return "Free up disk space and try again."
            
        case .microphoneDisconnected:
            return "Reconnect the microphone and start a new recording."
            
        default:
            return "Please try again or restart the app."
        }
    }
}
