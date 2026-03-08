import OpenClawChatUI
import SwiftUI

@main
struct OpenClawTVApp: App {
    @State private var model = TVGatewayChatModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(self.model)
                .onChange(of: self.scenePhase) { _, newValue in
                    self.model.scenePhaseChanged(newValue)
                }
        }
    }
}

struct TVRootView: View {
    @Environment(TVGatewayChatModel.self) private var model

    var body: some View {
        Group {
            if self.model.isConnected {
                TVChatScreen()
            } else {
                TVConnectionView(showsDoneButton: false)
            }
        }
        .task {
            self.model.loadSavedConfigAndAutoconnect()
        }
    }
}

private struct TVChatScreen: View {
    @Environment(TVGatewayChatModel.self) private var model
    @State private var showConnectionSettings = false

    var body: some View {
        NavigationStack {
            OpenClawChatView(
                viewModel: self.model.chatViewModel,
                showsSessionSwitcher: true)
                .navigationTitle("Chat")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Connection") {
                            self.showConnectionSettings = true
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Disconnect") {
                            self.model.disconnect()
                        }
                    }
                }
        }
        .sheet(isPresented: self.$showConnectionSettings) {
            TVConnectionView(showsDoneButton: true)
                .environment(self.model)
        }
    }
}

struct TVConnectionView: View {
    @Environment(TVGatewayChatModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let showsDoneButton: Bool

    private var promptBinding: Binding<TVGatewayChatModel.TrustPrompt?> {
        Binding(
            get: { self.model.pendingTrustPrompt },
            set: { _ in })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("Host", text: self.$model.manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Port (optional)", text: self.$model.manualPortText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("Use TLS", isOn: self.$model.manualUseTLS)

                    TextField("Gateway token", text: self.$model.manualToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Gateway password", text: self.$model.manualPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Status") {
                    Text(self.model.statusText)
                    if let errorText = self.model.errorText?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !errorText.isEmpty
                    {
                        Text(errorText)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(self.model.isConnecting ? "Connecting…" : "Connect") {
                        self.model.connectManual()
                    }
                    .disabled(self.model.isConnecting)

                    if self.model.isConnected {
                        Button("Disconnect") {
                            self.model.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                if self.showsDoneButton {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") {
                            self.dismiss()
                        }
                    }
                }
            }
        }
        .alert(item: self.promptBinding) { prompt in
            Alert(
                title: Text("Trust this gateway?"),
                message: Text(
                    """
                    First-time TLS connection.

                    Verify this SHA-256 fingerprint before trusting:
                    \(prompt.fingerprintSha256)
                    """),
                primaryButton: .cancel(Text("Cancel")) {
                    self.model.declineTrustPrompt()
                },
                secondaryButton: .default(Text("Trust and connect")) {
                    self.model.acceptTrustPrompt()
                })
        }
    }
}
