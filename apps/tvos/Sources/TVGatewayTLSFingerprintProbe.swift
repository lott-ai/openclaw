import CryptoKit
import Foundation
import Security

private final class TVGatewayTLSFingerprintProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private struct ProbeState {
        var didFinish = false
        var session: URLSession?
        var task: URLSessionWebSocketTask?
    }

    private let url: URL
    private let timeoutSeconds: Double
    private let onComplete: (String?) -> Void
    private let state = OSAllocatedUnfairLock(initialState: ProbeState())

    init(url: URL, timeoutSeconds: Double, onComplete: @escaping (String?) -> Void) {
        self.url = url
        self.timeoutSeconds = timeoutSeconds
        self.onComplete = onComplete
    }

    func start() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = self.timeoutSeconds
        config.timeoutIntervalForResource = self.timeoutSeconds
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: self.url)
        self.state.withLock { current in
            current.session = session
            current.task = task
        }
        task.resume()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.timeoutSeconds) { [weak self] in
            self?.finish(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let fingerprint = Self.certificateFingerprint(trust)
        completionHandler(.cancelAuthenticationChallenge, nil)
        self.finish(fingerprint)
    }

    private func finish(_ fingerprint: String?) {
        let (shouldComplete, taskToCancel, sessionToInvalidate) = self.state.withLock { current -> (Bool, URLSessionWebSocketTask?, URLSession?) in
            guard !current.didFinish else { return (false, nil, nil) }
            current.didFinish = true
            let task = current.task
            let session = current.session
            current.task = nil
            current.session = nil
            return (true, task, session)
        }

        guard shouldComplete else { return }
        taskToCancel?.cancel(with: .goingAway, reason: nil)
        sessionToInvalidate?.invalidateAndCancel()
        self.onComplete(fingerprint)
    }

    private static func certificateFingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let cert = chain.first
        else {
            return nil
        }
        return Self.sha256Hex(SecCertificateCopyData(cert) as Data)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
