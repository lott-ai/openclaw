import OpenClawChatUI
import OpenClawKit
import SwiftUI
import Testing
import UIKit
@testable import OpenClawTV

@Suite struct TVSwiftUIRenderSmokeTests {
    @MainActor private static func host(_ view: some View) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    @Test @MainActor func connectionViewBuildsAViewHierarchy() {
        let model = TVGatewayChatModel()
        _ = Self.host(
            TVConnectionView(showsDoneButton: false)
                .environment(model))
    }

    @Test @MainActor func chatViewBuildsAViewHierarchy() {
        let transport = TestTransport()
        let viewModel = OpenClawChatViewModel(sessionKey: "tvos", transport: transport)
        _ = Self.host(
            OpenClawChatView(
                viewModel: viewModel,
                showsSessionSwitcher: true))
    }
}

private struct TestTransport: OpenClawChatTransport, Sendable {
    func requestHistory(sessionKey: String) async throws -> OpenClawChatHistoryPayload {
        OpenClawChatHistoryPayload(
            sessionKey: sessionKey,
            sessionId: nil,
            messages: [],
            thinkingLevel: "off")
    }

    func sendMessage(
        sessionKey _: String,
        message _: String,
        thinking _: String,
        idempotencyKey: String,
        attachments _: [OpenClawChatAttachmentPayload]) async throws -> OpenClawChatSendResponse
    {
        OpenClawChatSendResponse(runId: idempotencyKey, status: "ok")
    }

    func abortRun(sessionKey _: String, runId _: String) async throws {}

    func listSessions(limit _: Int?) async throws -> OpenClawChatSessionsListResponse {
        OpenClawChatSessionsListResponse(ts: nil, path: nil, count: 0, defaults: nil, sessions: [])
    }

    func requestHealth(timeoutMs _: Int) async throws -> Bool {
        true
    }

    func events() -> AsyncStream<OpenClawChatTransportEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
