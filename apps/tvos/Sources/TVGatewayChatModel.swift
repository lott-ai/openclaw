import OpenClawChatUI
import OpenClawKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TVGatewayChatModel {
    struct TrustPrompt: Identifiable, Equatable {
        let stableID: String
        let host: String
        let port: Int
        let fingerprintSha256: String

        var id: String { self.stableID }
    }

    struct ResolvedGatewayConfig: Equatable, Sendable {
        let host: String
        let port: Int
        let useTLS: Bool
        let token: String?
        let password: String?

        var url: URL? {
            var components = URLComponents()
            components.scheme = self.useTLS ? "wss" : "ws"
            components.host = self.host
            components.port = self.port
            return components.url
        }

        var stableID: String {
            "manual|\(self.host.lowercased())|\(self.port)"
        }
    }

    static let defaultSessionKey = "tvos"
    static let compatibleClientID = "openclaw-ios"

    var manualHost: String = ""
    var manualPortText: String = ""
    var manualUseTLS: Bool = true
    var manualToken: String = ""
    var manualPassword: String = ""

    var statusText: String = "Not connected"
    var errorText: String?
    var isConnecting: Bool = false
    var isConnected: Bool = false
    var pendingTrustPrompt: TrustPrompt?

    let chatViewModel: OpenClawChatViewModel

    @ObservationIgnored private let gateway: GatewayNodeSession
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTrustConfig: ResolvedGatewayConfig?
    @ObservationIgnored private var autoReconnectEnabled = false
    @ObservationIgnored private var didAttemptInitialConnect = false

    init() {
        let gateway = GatewayNodeSession()
        self.gateway = gateway
        self.chatViewModel = OpenClawChatViewModel(
            sessionKey: Self.defaultSessionKey,
            transport: TVGatewayChatTransport(gateway: gateway))

        if let saved = TVGatewaySettingsStore.loadSavedConnection() {
            self.manualHost = saved.host
            self.manualPortText = String(saved.port)
            self.manualUseTLS = saved.useTLS
            self.autoReconnectEnabled = true
        }
        self.manualToken = TVGatewaySettingsStore.loadToken() ?? ""
        self.manualPassword = TVGatewaySettingsStore.loadPassword() ?? ""
    }

    deinit {
        self.connectTask?.cancel()
    }

    func loadSavedConfigAndAutoconnect() {
        guard !self.didAttemptInitialConnect else { return }
        self.didAttemptInitialConnect = true
        self.maybeAutoReconnect()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        guard phase == .active else { return }
        self.maybeAutoReconnect()
    }

    func connectManual() {
        do {
            let config = try Self.resolveConnectionConfig(
                host: self.manualHost,
                portText: self.manualPortText,
                useTLS: self.manualUseTLS,
                token: self.manualToken,
                password: self.manualPassword)
            self.persistForm(config)
            self.autoReconnectEnabled = true
            self.connectOrPromptTrust(config)
        } catch {
            self.errorText = error.localizedDescription
            self.statusText = "Connect failed"
        }
    }

    func acceptTrustPrompt() {
        guard let prompt = self.pendingTrustPrompt,
              let config = self.pendingTrustConfig,
              config.stableID == prompt.stableID
        else {
            return
        }

        GatewayTLSStore.saveFingerprint(prompt.fingerprintSha256, stableID: prompt.stableID)
        self.pendingTrustPrompt = nil
        self.pendingTrustConfig = nil
        self.startConnect(config)
    }

    func declineTrustPrompt() {
        self.pendingTrustPrompt = nil
        self.pendingTrustConfig = nil
        self.statusText = "Trust cancelled"
    }

    func disconnect() {
        self.autoReconnectEnabled = false
        self.pendingTrustPrompt = nil
        self.pendingTrustConfig = nil
        self.connectTask?.cancel()
        self.connectTask = nil
        self.isConnecting = false
        self.isConnected = false
        self.statusText = "Disconnected"
        Task {
            await self.gateway.disconnect()
        }
    }

    static func resolveConnectionConfig(
        host: String,
        portText: String,
        useTLS: Bool,
        token: String,
        password: String) throws -> ResolvedGatewayConfig
    {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw NSError(domain: "TVGatewayChatModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Host is required.",
            ])
        }

        let resolvedUseTLS = Self.resolveManualUseTLS(host: trimmedHost, useTLS: useTLS)
        guard let resolvedPort = Self.resolveManualPort(host: trimmedHost, portText: portText, useTLS: resolvedUseTLS) else {
            throw NSError(domain: "TVGatewayChatModel", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Port must be between 1 and 65535.",
            ])
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        return ResolvedGatewayConfig(
            host: trimmedHost,
            port: resolvedPort,
            useTLS: resolvedUseTLS,
            token: trimmedToken.isEmpty ? nil : trimmedToken,
            password: trimmedPassword.isEmpty ? nil : trimmedPassword)
    }

    static func resolveManualUseTLS(host: String, useTLS: Bool) -> Bool {
        useTLS || !LoopbackHost.isLoopbackHost(host)
    }

    static func resolveManualPort(host: String, portText: String, useTLS: Bool) -> Int? {
        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPort.isEmpty {
            guard let port = Int(trimmedPort), (1...65535).contains(port) else { return nil }
            return port
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return nil }
        if useTLS && normalizedHost.hasSuffix(".ts.net") {
            return 443
        }
        return 18789
    }

    private func maybeAutoReconnect() {
        guard self.autoReconnectEnabled else { return }
        guard !self.isConnected, !self.isConnecting else { return }
        guard let saved = TVGatewaySettingsStore.loadSavedConnection() else { return }

        self.manualHost = saved.host
        self.manualPortText = String(saved.port)
        self.manualUseTLS = saved.useTLS
        self.manualToken = TVGatewaySettingsStore.loadToken() ?? ""
        self.manualPassword = TVGatewaySettingsStore.loadPassword() ?? ""

        do {
            let config = try Self.resolveConnectionConfig(
                host: saved.host,
                portText: String(saved.port),
                useTLS: saved.useTLS,
                token: self.manualToken,
                password: self.manualPassword)
            self.connectOrPromptTrust(config)
        } catch {
            self.errorText = error.localizedDescription
            self.statusText = "Connect failed"
        }
    }

    private func connectOrPromptTrust(_ config: ResolvedGatewayConfig) {
        guard config.useTLS else {
            self.startConnect(config)
            return
        }

        if GatewayTLSStore.loadFingerprint(stableID: config.stableID) != nil {
            self.startConnect(config)
            return
        }

        guard let url = config.url else {
            self.errorText = "Failed to build the gateway URL."
            return
        }

        self.isConnecting = true
        self.statusText = "Checking TLS fingerprint…"
        self.errorText = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let fingerprint = await Self.probeTLSFingerprint(url: url)
            guard let fingerprint else {
                self.isConnecting = false
                self.statusText = "Connect failed"
                self.errorText = "Failed to read the gateway TLS fingerprint."
                return
            }

            self.isConnecting = false
            self.pendingTrustConfig = config
            self.pendingTrustPrompt = TrustPrompt(
                stableID: config.stableID,
                host: config.host,
                port: config.port,
                fingerprintSha256: fingerprint)
            self.statusText = "Trust the gateway to continue"
        }
    }

    private func startConnect(_ config: ResolvedGatewayConfig) {
        guard let url = config.url else {
            self.errorText = "Failed to build the gateway URL."
            self.statusText = "Connect failed"
            return
        }

        self.pendingTrustPrompt = nil
        self.pendingTrustConfig = nil
        self.connectTask?.cancel()
        self.isConnecting = true
        self.errorText = nil
        self.statusText = self.isConnected ? "Reconnecting…" : "Connecting…"

        let fingerprint = GatewayTLSStore.loadFingerprint(stableID: config.stableID)
        let sessionBox = (config.useTLS || fingerprint != nil)
            ? WebSocketSessionBox(session: GatewayTLSPinningSession(params: GatewayTLSParams(
                required: true,
                expectedFingerprint: fingerprint,
                allowTOFU: false,
                storeKey: config.stableID)))
            : nil

        self.connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.gateway.connect(
                    url: url,
                    token: config.token,
                    password: config.password,
                    connectOptions: Self.makeOperatorConnectOptions(),
                    sessionBox: sessionBox,
                    onConnected: { [weak self] in
                        guard let self else { return }
                        await MainActor.run {
                            self.isConnecting = false
                            self.isConnected = true
                            self.statusText = "Connected"
                            self.errorText = nil
                            self.persistForm(config)
                            self.chatViewModel.refresh()
                        }
                    },
                    onDisconnected: { [weak self] reason in
                        guard let self else { return }
                        await MainActor.run {
                            self.isConnecting = false
                            self.isConnected = false
                            self.statusText = "Disconnected"
                            self.errorText = reason
                        }
                    },
                    onInvoke: { request in
                        BridgeInvokeResponse(
                            id: request.id,
                            ok: false,
                            error: OpenClawNodeError(
                                code: .unavailable,
                                message: "UNAVAILABLE: tvOS operator client"))
                    })
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.isConnecting = false
                    self.isConnected = false
                    self.statusText = "Connect failed"
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func persistForm(_ config: ResolvedGatewayConfig) {
        self.manualHost = config.host
        self.manualPortText = String(config.port)
        self.manualUseTLS = config.useTLS
        self.manualToken = config.token ?? ""
        self.manualPassword = config.password ?? ""
        TVGatewaySettingsStore.saveSavedConnection(
            TVGatewaySavedConnection(host: config.host, port: config.port, useTLS: config.useTLS))
        TVGatewaySettingsStore.saveToken(config.token)
        TVGatewaySettingsStore.savePassword(config.password)
    }

    private static func makeOperatorConnectOptions() -> GatewayConnectOptions {
        GatewayConnectOptions(
            role: "operator",
            scopes: ["operator.read", "operator.write", "operator.talk.secrets"],
            caps: [],
            commands: [],
            permissions: [:],
            clientId: Self.compatibleClientID,
            clientMode: "ui",
            clientDisplayName: InstanceIdentity.displayName,
            includeDeviceIdentity: true)
    }

    private static func probeTLSFingerprint(url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let probe = TVGatewayTLSFingerprintProbe(url: url, timeoutSeconds: 3) { fingerprint in
                continuation.resume(returning: fingerprint)
            }
            probe.start()
        }
    }
}
