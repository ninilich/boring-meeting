import Foundation
import SwiftData

// MARK: - HTTP request/response types

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data?
}

struct HTTPResponse {
    let status: Int
    let body: String
    var contentType: String = "application/json"
}

// MARK: - Response DTOs

private struct MeetingDTO: Encodable {
    let id: String
    let title: String
    let date: String
    let duration: TimeInterval
    let fileSize: Int64
    let transcriptionStatus: String
    let progress: Double
    let isTranscribed: Bool
    let transcriptionError: String?
}

private struct MeetingListDTO: Encodable {
    let meetings: [MeetingDTO]
    let total: Int
}

private struct ErrorDTO: Encodable {
    let error: String
}

private struct StatusDTO: Encodable {
    let status: String
}

// MARK: - Router

extension CLIAPIServer {
    func route(raw: String) async -> HTTPResponse {
        guard let request = parseHTTPRequest(raw) else {
            return HTTPResponse(status: 400, body: encode(ErrorDTO(error: "bad_request")))
        }

        let m = request.method
        let s = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if m == "GET" && s == ["meetings"] {
            return await handleListMeetings()
        } else if m == "GET" && s.count == 2 && s[0] == "meetings" {
            return await handleGetMeeting(id: s[1])
        } else if m == "GET" && s.count == 3 && s[0] == "meetings" && s[2] == "transcript" {
            return await handleGetTranscript(id: s[1])
        } else if m == "POST" && s.count == 3 && s[0] == "meetings" && s[2] == "transcribe" {
            return await handleStartTranscription(id: s[1])
        } else if m == "PATCH" && s.count == 2 && s[0] == "meetings" {
            return await handleRenameMeeting(id: s[1], body: request.body)
        } else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "not_found")))
        }
    }

    // MARK: - Handlers

    private func handleListMeetings() async -> HTTPResponse {
        let ctx = modelContainer.mainContext
        let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let meetings = try? ctx.fetch(descriptor) else {
            return HTTPResponse(status: 500, body: encode(ErrorDTO(error: "db_error")))
        }
        let dtos = meetings.map { meetingDTO($0) }
        return HTTPResponse(status: 200, body: encode(MeetingListDTO(meetings: dtos, total: dtos.count)))
    }

    private func handleGetMeeting(id: String) async -> HTTPResponse {
        guard let meeting = fetchMeeting(id: id) else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "not_found")))
        }
        return HTTPResponse(status: 200, body: encode(meetingDTO(meeting)))
    }

    private func handleGetTranscript(id: String) async -> HTTPResponse {
        guard let meeting = fetchMeeting(id: id) else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "not_found")))
        }
        guard meeting.isTranscribed, !meeting.transcript.isEmpty else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "transcript_not_available")))
        }
        return HTTPResponse(status: 200, body: meeting.transcript, contentType: "text/plain")
    }

    private func handleStartTranscription(id: String) async -> HTTPResponse {
        guard let meeting = fetchMeeting(id: id) else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "not_found")))
        }

        if transcriptionManager.isRunning(for: meeting.id) {
            return HTTPResponse(status: 409, body: encode(ErrorDTO(error: "already_running")))
        }

        let modelID = AppSettings.shared.defaultTranscriptionModelID
        do {
            if AppSettings.shared.splitAudioSources {
                try transcriptionManager.startDualSourceTranscription(for: meeting, modelID: modelID)
            } else {
                try transcriptionManager.startTranscription(for: meeting, modelID: modelID)
            }
            return HTTPResponse(status: 202, body: encode(StatusDTO(status: "transcription_started")))
        } catch {
            return HTTPResponse(status: 400, body: encode(ErrorDTO(error: error.localizedDescription)))
        }
    }

    private func handleRenameMeeting(id: String, body: Data?) async -> HTTPResponse {
        guard let meeting = fetchMeeting(id: id) else {
            return HTTPResponse(status: 404, body: encode(ErrorDTO(error: "not_found")))
        }

        struct RenameBody: Decodable { let title: String }
        guard let body,
              let payload = try? JSONDecoder().decode(RenameBody.self, from: body),
              !payload.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return HTTPResponse(status: 400, body: encode(ErrorDTO(error: "title_required")))
        }

        meeting.title = payload.title.trimmingCharacters(in: .whitespaces)
        try? modelContainer.mainContext.save()
        return HTTPResponse(status: 200, body: encode(meetingDTO(meeting)))
    }

    // MARK: - Helpers

    private func fetchMeeting(id: String) -> Meeting? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let ctx = modelContainer.mainContext
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == uuid })
        return try? ctx.fetch(descriptor).first
    }

    private func meetingDTO(_ meeting: Meeting) -> MeetingDTO {
        MeetingDTO(
            id: meeting.id.uuidString,
            title: meeting.title,
            date: ISO8601DateFormatter().string(from: meeting.date),
            duration: meeting.duration,
            fileSize: meeting.fileSize,
            transcriptionStatus: meeting.transcriptionStatus,
            progress: transcriptionManager.progress(for: meeting.id),
            isTranscribed: meeting.isTranscribed,
            transcriptionError: meeting.transcriptionError
        )
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"error":"encoding_failed"}"#
        }
        return str
    }

    private func parseHTTPRequest(_ raw: String) -> HTTPRequest? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let fullPath = parts[1]
        let path = fullPath.components(separatedBy: "?").first ?? fullPath

        // Extract body (after double CRLF)
        var body: Data?
        if let bodyRange = raw.range(of: "\r\n\r\n") {
            let bodyStr = String(raw[bodyRange.upperBound...])
            if !bodyStr.isEmpty {
                body = bodyStr.data(using: .utf8)
            }
        }

        return HTTPRequest(method: method, path: path, body: body)
    }
}
