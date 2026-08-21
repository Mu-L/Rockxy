@testable import Rockxy
import Testing

struct RequestBodyLimitStateTests {
    @Test("Request body overflow latches rejection until reset")
    func overflowLatchesRejection() {
        var state = RequestBodyLimitState()

        let acceptedPrefix = state.accept(6, maximum: 10)
        let acceptedOverflow = state.accept(5, maximum: 10)
        #expect(acceptedPrefix)
        #expect(!acceptedOverflow)
        #expect(state.isRejected)
        let acceptedAfterRejection = state.accept(1, maximum: 10)
        #expect(!acceptedAfterRejection)

        state.reset()

        #expect(!state.isRejected)
        let acceptedAtLimit = state.accept(10, maximum: 10)
        #expect(acceptedAtLimit)
    }
}
