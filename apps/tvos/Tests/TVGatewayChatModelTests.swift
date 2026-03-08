import Testing
@testable import OpenClawTV

@Suite struct TVGatewayChatModelTests {
    @Test func resolvesRemoteHostToTLSAndDefaultPort() throws {
        let config = try TVGatewayChatModel.resolveConnectionConfig(
            host: "gateway.example.ts.net",
            portText: "",
            useTLS: false,
            token: "tok",
            password: "")

        #expect(config.useTLS)
        #expect(config.port == 443)
        #expect(config.stableID == "manual|gateway.example.ts.net|443")
        #expect(config.token == "tok")
    }

    @Test func keepsExplicitPortForLoopbackHost() throws {
        let config = try TVGatewayChatModel.resolveConnectionConfig(
            host: "127.0.0.1",
            portText: "18789",
            useTLS: false,
            token: "",
            password: "")

        #expect(!config.useTLS)
        #expect(config.port == 18789)
        #expect(config.url?.absoluteString == "ws://127.0.0.1:18789")
    }

    @Test func rejectsInvalidPort() {
        #expect(throws: (any Error).self) {
            _ = try TVGatewayChatModel.resolveConnectionConfig(
                host: "gateway.local",
                portText: "99999",
                useTLS: true,
                token: "",
                password: "")
        }
    }
}
