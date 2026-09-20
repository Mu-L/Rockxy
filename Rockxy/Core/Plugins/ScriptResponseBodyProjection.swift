import Foundation

/// The response a script sees. Captured bodies keep the origin's `Content-Encoding`, so a
/// gzip/deflate/Brotli JSON response would otherwise reach `onResponse` as an opaque
/// base64 blob and every documented body edit would silently fail. The projection decodes
/// the body up front and drops the headers that only described the compressed
/// representation; the relay recomputes `Content-Length` from whatever the script returns.
/// Bodies that cannot be decoded keep their original bytes and headers.
struct ScriptResponseBodyProjection {
    // MARK: Lifecycle

    init(response: HTTPResponseData) {
        guard let rawBody = response.body, !rawBody.isEmpty else {
            headers = response.headers
            body = response.body
            didDecode = false
            return
        }
        let contentEncoding = response.headers.first { $0.name.lowercased() == "content-encoding" }?.value
        let decoded = BodyDecoder.decodeReportingChange(rawBody, encoding: contentEncoding)
        guard decoded.didDecode else {
            headers = response.headers
            body = rawBody
            didDecode = false
            return
        }
        headers = response.headers.filter { header in
            let name = header.name.lowercased()
            return name != "content-encoding" && name != "content-length"
        }
        body = decoded.data
        didDecode = true
    }

    // MARK: Internal

    /// Headers coherent with `body`.
    let headers: [HTTPHeader]
    /// The decoded body when decoding succeeded, otherwise the captured bytes.
    let body: Data?
    let didDecode: Bool
}
