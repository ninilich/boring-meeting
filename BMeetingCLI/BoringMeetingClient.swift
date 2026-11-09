import ArgumentParser
import Foundation

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case json
    case text
}

struct BoringMeetingClient {
    let baseURL: URL

    init() {
        let port = ProcessInfo.processInfo.environment["BMEETING_PORT"]
            .flatMap(Int.init) ?? 49484
        baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    func get(_ path: String) throws -> Data {
        return try request(method: "GET", path: path, body: nil)
    }

    func post(_ path: String, body: Data? = nil) throws -> Data {
        return try request(method: "POST", path: path, body: body)
    }

    func patch(_ path: String, body: Data) throws -> Data {
        return try request(method: "PATCH", path: path, body: body)
    }

    private func request(method: String, path: String, body: Data?) throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CLIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10

        var result: Result<Data, Error> = .failure(CLIError.timeout)
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data {
                result = .success(data)
            } else {
                result = .failure(CLIError.emptyResponse)
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return try result.get()
    }
}

enum CLIError: Error, LocalizedError {
    case invalidURL
    case timeout
    case emptyResponse
    case apiError(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .timeout: return "Request timed out. Is BoringMeeting running with CLI API enabled?"
        case .emptyResponse: return "Empty response from server"
        case .apiError(let msg): return msg
        case .notRunning: return "Cannot connect to BoringMeeting. Make sure the app is running and CLI API is enabled in Settings."
        }
    }
}

// MARK: - Helpers

func printOutput<T: Encodable>(_ value: T, format: OutputFormat) {
    switch format {
    case .json:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    case .text:
        print("\(value)")
    }
}

func decodeOrExit<T: Decodable>(_ type: T.Type, from data: Data) -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        fputs("Error: failed to parse server response — \(error)\n", stderr)
        exit(1)
    }
}

func handleConnectionError(_ error: Error) -> Never {
    let msg = (error as NSError).code == -1004 || (error as NSError).code == -1
        ? "Cannot connect to BoringMeeting. Make sure the app is running and CLI API is enabled in Settings."
        : error.localizedDescription
    fputs("Error: \(msg)\n", stderr)
    exit(1)
}
