import Foundation
import Network
import SwiftData

@MainActor
final class CLIAPIServer {
    let modelContainer: ModelContainer
    let transcriptionManager: TranscriptionManager
    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var port: Int = 49484

    init(modelContainer: ModelContainer, transcriptionManager: TranscriptionManager) {
        self.modelContainer = modelContainer
        self.transcriptionManager = transcriptionManager
    }

    func start(on port: Int) {
        stop()
        self.port = port

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 49484
        )

        guard let listener = try? NWListener(using: params) else {
            print("❌ CLIAPIServer: failed to create listener on port \(port)")
            return
        }

        // NWListener callbacks are called on the queue passed to start().
        // We bridge back to MainActor for all data access.
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handleConnection(connection)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("✅ CLIAPIServer: listening on localhost:\(port)")
            case .failed(let error):
                print("❌ CLIAPIServer: listener failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .utility))
        self.listener = listener
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }

                guard self.isLocalhost(connection) else {
                    self.sendResponse(status: 403, body: #"{"error":"forbidden"}"#, to: connection)
                    return
                }

                guard let data, !data.isEmpty,
                      let raw = String(data: data, encoding: .utf8) else {
                    self.sendResponse(status: 400, body: #"{"error":"bad_request"}"#, to: connection)
                    return
                }

                let response = await self.route(raw: raw)
                self.sendResponse(status: response.status, body: response.body, contentType: response.contentType, to: connection)
            }
        }
    }

    private func isLocalhost(_ connection: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = connection.endpoint else { return false }
        switch host {
        case .ipv4(let addr): return addr == .loopback
        case .ipv6(let addr): return addr == .loopback
        case .name(let name, _): return name == "localhost" || name == "127.0.0.1" || name == "::1"
        @unknown default: return false
        }
    }

    func sendResponse(status: Int, body: String, contentType: String = "application/json", to connection: NWConnection) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = header.data(using: .utf8)!
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}
