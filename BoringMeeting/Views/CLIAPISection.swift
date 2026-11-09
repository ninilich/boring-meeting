import SwiftUI

struct CLIAPISection: View {
    @ObservedObject var settings: AppSettings
    let appDelegate: AppDelegate

    @State private var cliInstalled: Bool = false
    @State private var showHelp = false
    @State private var isInstallingCLI = false
    @State private var cliInstallError: String?
    @State private var showCLIInstallError = false

    private var serverStatus: String {
        guard settings.cliAPIEnabled else { return "Stopped" }
        return appDelegate.cliAPIServer.isRunning ? "Running" : "Starting…"
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { "\(settings.cliAPIPort)" },
            set: { newValue in
                if let port = Int(newValue), port > 1024, port <= 65535 {
                    settings.cliAPIPort = port
                }
            }
        )
    }

    private var serverStatusColor: Color {
        appDelegate.cliAPIServer.isRunning ? .green : .secondary
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Toggle("Enable CLI API", isOn: $settings.cliAPIEnabled)
                        .disabled(!cliInstalled)
                        .help(cliInstalled ? "" : "Install bmeeting CLI first")
                    Spacer()
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: portBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .disabled(settings.cliAPIEnabled)
                        .controlSize(.small)
                }
                if !cliInstalled {
                    Text("Install bmeeting CLI first to enable the API server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(serverStatusColor)
                    .frame(width: 8, height: 8)
                Text(serverStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                if cliInstalled {
                    Button("Uninstall bmeeting CLI") {
                        uninstallCLI()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isInstallingCLI)
                } else {
                    Button("Install bmeeting CLI") {
                        installCLI()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstallingCLI)
                }

                if isInstallingCLI {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Spacer()

                Text("Requires admin password")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Label("CLI API", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHelp, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("bmeeting")
                            .font(.headline)
                        Text("A command-line tool for interacting with BoringMeeting — automate meeting management, trigger transcription, retrieve transcripts, and more. Designed for use with AI tools and scripts.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Text("To see all available commands, run in Terminal:")
                            .font(.callout)
                        Text("bmeeting --help")
                            .font(.system(.callout, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label("BoringMeeting must be running", systemImage: "checkmark.circle")
                            Label("CLI API must be enabled in this section", systemImage: "checkmark.circle")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(width: 320)
                }
            }
        }
        .onAppear {
            refreshCLIInstallStatus()
        }
        .alert("CLI Error", isPresented: $showCLIInstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cliInstallError ?? "Unknown error")
        }
    }

    private func refreshCLIInstallStatus() {
        cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/bmeeting")
    }

    private func uninstallCLI() {
        isInstallingCLI = true
        let script = "do shell script \"rm /usr/local/bin/bmeeting\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                isInstallingCLI = false
                if let errorInfo = error {
                    let msg = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    if !msg.contains("User canceled") {
                        cliInstallError = msg
                        showCLIInstallError = true
                    }
                } else {
                    refreshCLIInstallStatus()
                    if !cliInstalled {
                        settings.cliAPIEnabled = false
                    }
                }
            }
        }
    }

    private func installCLI() {
        guard let bundleCLIPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("bmeeting")
            .path else {
            cliInstallError = "bmeeting binary not found in app bundle."
            showCLIInstallError = true
            return
        }

        guard FileManager.default.fileExists(atPath: bundleCLIPath) else {
            cliInstallError = "bmeeting binary not found at: \(bundleCLIPath)"
            showCLIInstallError = true
            return
        }

        isInstallingCLI = true
        let script = "do shell script \"ln -sf '\(bundleCLIPath)' '/usr/local/bin/bmeeting'\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                isInstallingCLI = false
                if let errorInfo = error {
                    let msg = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    if !msg.contains("User canceled") {
                        cliInstallError = msg
                        showCLIInstallError = true
                    }
                } else {
                    refreshCLIInstallStatus()
                }
            }
        }
    }
}
