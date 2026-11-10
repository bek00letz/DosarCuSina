import Foundation
import Testing
@testable import DosarCuSina

/// A Vision pass that fails is tried once more after the reader's named backoff, and not
/// at all once the reading is cancelled.
@Suite("Vision retry")
struct VisionRetryTests {
    private actor Tries {
        private(set) var count = 0
        func next() -> Int { count += 1; return count }
    }

    private struct Failed: Error {}

    @Test func aFailedPassIsTriedOnceMore() async {
        let tries = Tries()
        let read = await VisionCaptureRecognizer.attempt("test", pause: .zero) { () async throws -> String in
            if await tries.next() == 1 { throw Failed() }
            return "Total de plată"
        }
        #expect(read == "Total de plată")
        #expect(await tries.count == 2)
    }

    @Test func twoFailuresGiveNothing() async {
        let tries = Tries()
        let read: String? = await VisionCaptureRecognizer.attempt("test", pause: .zero) {
            _ = await tries.next()
            throw Failed()
        }
        #expect(read == nil)
        #expect(await tries.count == 2, "Once more, never a third time")
    }

    @Test func aCancelledReadingIsNotTriedAgain() async {
        let tries = Tries()
        let reading = Task {
            await VisionCaptureRecognizer.attempt("test", pause: .seconds(60)) { () async throws -> String in
                _ = await tries.next()
                throw Failed()
            }
        }
        while await tries.count == 0 { await Task.yield() }
        reading.cancel()
        #expect(await reading.value == nil)
        #expect(await tries.count == 1, "Cancelled during the backoff: no second try")
    }
}
