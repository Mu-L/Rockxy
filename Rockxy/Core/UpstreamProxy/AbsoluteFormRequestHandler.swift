import Foundation
import NIOCore
import NIOHTTP1

// Rewrites relayed plain-HTTP requests into the absolute form an HTTP proxy expects.

// MARK: - AbsoluteFormRequestHandler

/// HTTP proxies take plain `http://` traffic as `GET http://host:port/path HTTP/1.1` on the
/// proxy connection itself; `CONNECT` tunnels are for TLS and many proxies (Squid's default
/// policy, most corporate gateways) refuse `CONNECT` to port 80. This outbound handler sits at
/// the tail of the upstream pipeline and turns the origin-form request line the relay writes
/// into the absolute form, adding `Proxy-Authorization` when the proxy needs credentials.
final class AbsoluteFormRequestHandler: ChannelOutboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(targetScheme: String, targetHost: String, targetPort: Int, credentials: UpstreamProxyCredentials?) {
        self.targetScheme = targetScheme.lowercased()
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.credentials = credentials
    }

    // MARK: Internal

    typealias OutboundIn = HTTPClientRequestPart
    typealias OutboundOut = HTTPClientRequestPart

    /// Builds `scheme://host[:port]/path?query` from an origin-form URI. A URI that is already
    /// absolute is passed through untouched; the default port is omitted from the authority.
    nonisolated static func absoluteURI(scheme: String, host: String, port: Int, originFormURI: String) -> String {
        let lowered = originFormURI.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return originFormURI
        }
        let defaultPort = scheme == "https" ? 443 : 80
        let authorityHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let authority = port == defaultPort ? authorityHost : "\(authorityHost):\(port)"
        let path = originFormURI.hasPrefix("/") ? originFormURI : "/\(originFormURI)"
        return "\(scheme)://\(authority)\(path)"
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard case var .head(head) = unwrapOutboundIn(data) else {
            context.write(data, promise: promise)
            return
        }
        head.uri = Self.absoluteURI(
            scheme: targetScheme,
            host: targetHost,
            port: targetPort,
            originFormURI: head.uri
        )
        if let credentials {
            let rawValue = "\(credentials.username):\(credentials.password)"
            let encoded = Data(rawValue.utf8).base64EncodedString()
            head.headers.replaceOrAdd(name: "Proxy-Authorization", value: "Basic \(encoded)")
        }
        context.write(wrapOutboundOut(.head(head)), promise: promise)
    }

    // MARK: Private

    private let targetScheme: String
    private let targetHost: String
    private let targetPort: Int
    private let credentials: UpstreamProxyCredentials?
}
