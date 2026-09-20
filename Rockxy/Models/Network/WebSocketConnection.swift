import Foundation

/// Thread-safe container for a WebSocket connection's upgrade request and captured frames.
/// Marked `@unchecked Sendable` because frame access is serialized through an `NSLock`.
final class WebSocketConnection: @unchecked Sendable {
    // MARK: Lifecycle

    init(upgradeRequest: HTTPRequestData, frames: [WebSocketFrameData] = []) {
        self.upgradeRequest = upgradeRequest
        self._frames = frames
        self._totalPayloadSize = frames.reduce(0) { $0 + $1.payload.count }
        self._sentPayloadSize = frames.reduce(0) { $0 + ($1.direction == .sent ? $1.payload.count : 0) }
        self._receivedPayloadSize = frames.reduce(0) { $0 + ($1.direction == .received ? $1.payload.count : 0) }
    }

    // MARK: Internal

    let upgradeRequest: HTTPRequestData

    var totalPayloadSize: Int {
        lock.withLock { _totalPayloadSize }
    }

    /// Payload bytes by direction, kept as running totals so per-connection byte accounting
    /// never has to walk the frame array.
    var sentPayloadSize: Int {
        lock.withLock { _sentPayloadSize }
    }

    var receivedPayloadSize: Int {
        lock.withLock { _receivedPayloadSize }
    }

    var frames: [WebSocketFrameData] {
        lock.withLock { _frames }
    }

    var frameCount: Int {
        lock.withLock { _frames.count }
    }

    var isCaptureLimitReached: Bool {
        lock.withLock { _isCaptureLimitReached }
    }

    var sentFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .sent } }
    }

    var receivedFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .received } }
    }

    func addFrame(_ frame: WebSocketFrameData) {
        lock.withLock {
            appendLocked(frame)
        }
    }

    @discardableResult
    func addFrame(_ frame: WebSocketFrameData, maximumTotalPayloadSize: Int) -> Bool {
        addFrame(
            frame,
            maximumTotalPayloadSize: maximumTotalPayloadSize,
            maximumFrameCount: .max
        )
    }

    @discardableResult
    func addFrame(
        _ frame: WebSocketFrameData,
        maximumTotalPayloadSize: Int,
        maximumFrameCount: Int
    )
        -> Bool
    {
        lock.withLock {
            guard !_isCaptureLimitReached else {
                return false
            }
            guard _frames.count < maximumFrameCount,
                  frame.payload.count <= maximumTotalPayloadSize,
                  _totalPayloadSize <= maximumTotalPayloadSize - frame.payload.count else
            {
                _isCaptureLimitReached = true
                return false
            }
            appendLocked(frame)
            return true
        }
    }

    func stopCaptureAtLimit() {
        lock.withLock {
            _isCaptureLimitReached = true
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _frames: [WebSocketFrameData]
    private var _totalPayloadSize: Int
    private var _sentPayloadSize: Int
    private var _receivedPayloadSize: Int
    private var _isCaptureLimitReached = false

    /// Caller holds `lock`.
    private func appendLocked(_ frame: WebSocketFrameData) {
        _frames.append(frame)
        _totalPayloadSize += frame.payload.count
        switch frame.direction {
        case .sent:
            _sentPayloadSize += frame.payload.count
        case .received:
            _receivedPayloadSize += frame.payload.count
        }
    }
}
