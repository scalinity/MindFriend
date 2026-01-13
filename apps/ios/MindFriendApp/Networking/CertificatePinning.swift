import Foundation
import Security
import CryptoKit

/// Certificate pinning implementation for enhanced API security
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {

    /// SHA-256 hashes of the public keys to pin
    /// Generate using: openssl s_client -connect api.mindfriend.app:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    private let pinnedPublicKeyHashes: Set<String> = [
        // Primary certificate pin (replace with actual hash)
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        // Backup certificate pin (replace with actual hash)
        "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    ]

    /// Domains that require certificate pinning
    private let pinnedDomains: Set<String> = [
        "api.mindfriend.app",
        "mindfriend.app"
    ]

    /// Whether pinning is enabled (disable for debugging)
    private let isPinningEnabled: Bool

    init(enabled: Bool = true) {
        #if DEBUG
        // Disable pinning in debug by default for easier testing
        self.isPinningEnabled = ProcessInfo.processInfo.environment["ENABLE_CERT_PINNING"] == "1"
        #else
        self.isPinningEnabled = enabled
        #endif
        super.init()
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard isPinningEnabled else {
            // Allow default handling when pinning is disabled
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host as String?,
              pinnedDomains.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        let isServerTrusted = SecTrustEvaluateWithError(serverTrust, &error)

        guard isServerTrusted else {
            CrashReporter.shared.capture(
                message: "Server trust evaluation failed",
                level: .warning,
                context: ["host": host, "error": error?.localizedDescription ?? "unknown"]
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract and verify the public key
        guard let serverCertificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !serverCertificate.isEmpty else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if any certificate in the chain matches our pinned hashes
        for certificate in serverCertificate {
            if let publicKeyHash = publicKeyHash(for: certificate),
               pinnedPublicKeyHashes.contains(publicKeyHash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No matching pin found
        CrashReporter.shared.capture(
            message: "Certificate pinning failed - no matching pin",
            level: .error,
            context: ["host": host]
        )

        Analytics.shared.track(.errorOccurred, properties: [
            "error_type": "certificate_pinning_failed",
            "host": host
        ])

        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Public Key Extraction

    /// Extract the SHA-256 hash of the public key from a certificate
    private func publicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Add the ASN.1 header for RSA keys
        let rsa2048ASN1Header: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]

        var keyWithHeader = Data(rsa2048ASN1Header)
        keyWithHeader.append(publicKeyData)

        let hash = SHA256.hash(data: keyWithHeader)
        return Data(hash).base64EncodedString()
    }
}

// MARK: - URLSession Extension

extension URLSession {
    /// Create a URLSession with certificate pinning enabled
    static func pinnedSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        let delegate = CertificatePinningDelegate()
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

// MARK: - Certificate Pinning Error

enum CertificatePinningError: Error, LocalizedError {
    case pinningFailed
    case invalidCertificate
    case trustEvaluationFailed

    var errorDescription: String? {
        switch self {
        case .pinningFailed:
            return "Certificate pinning verification failed"
        case .invalidCertificate:
            return "Invalid server certificate"
        case .trustEvaluationFailed:
            return "Server trust evaluation failed"
        }
    }
}
