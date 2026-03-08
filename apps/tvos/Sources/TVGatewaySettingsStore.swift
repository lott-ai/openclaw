import Foundation
import OpenClawKit

struct TVGatewaySavedConnection: Equatable, Sendable {
    let host: String
    let port: Int
    let useTLS: Bool
}

enum TVGatewaySettingsStore {
    private static let gatewayService = "ai.openclaw.tvos.gateway"
    private static let hostDefaultsKey = "tvos.gateway.host"
    private static let portDefaultsKey = "tvos.gateway.port"
    private static let tlsDefaultsKey = "tvos.gateway.tls"
    private static let tokenAccount = "manual-token"
    private static let passwordAccount = "manual-password"

    static func loadSavedConnection(defaults: UserDefaults = .standard) -> TVGatewaySavedConnection? {
        let host = defaults.string(forKey: self.hostDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { return nil }

        let port = defaults.integer(forKey: self.portDefaultsKey)
        guard (1...65535).contains(port) else { return nil }

        return TVGatewaySavedConnection(
            host: host,
            port: port,
            useTLS: defaults.bool(forKey: self.tlsDefaultsKey))
    }

    static func saveSavedConnection(_ connection: TVGatewaySavedConnection, defaults: UserDefaults = .standard) {
        defaults.set(connection.host, forKey: self.hostDefaultsKey)
        defaults.set(connection.port, forKey: self.portDefaultsKey)
        defaults.set(connection.useTLS, forKey: self.tlsDefaultsKey)
    }

    static func clearSavedConnection(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: self.hostDefaultsKey)
        defaults.removeObject(forKey: self.portDefaultsKey)
        defaults.removeObject(forKey: self.tlsDefaultsKey)
    }

    static func loadToken() -> String? {
        let token = GenericPasswordKeychainStore.loadString(
            service: self.gatewayService,
            account: self.tokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    static func saveToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            _ = GenericPasswordKeychainStore.delete(service: self.gatewayService, account: self.tokenAccount)
            return
        }
        _ = GenericPasswordKeychainStore.saveString(
            trimmed,
            service: self.gatewayService,
            account: self.tokenAccount)
    }

    static func loadPassword() -> String? {
        let password = GenericPasswordKeychainStore.loadString(
            service: self.gatewayService,
            account: self.passwordAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return password?.isEmpty == false ? password : nil
    }

    static func savePassword(_ password: String?) {
        let trimmed = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            _ = GenericPasswordKeychainStore.delete(service: self.gatewayService, account: self.passwordAccount)
            return
        }
        _ = GenericPasswordKeychainStore.saveString(
            trimmed,
            service: self.gatewayService,
            account: self.passwordAccount)
    }
}
