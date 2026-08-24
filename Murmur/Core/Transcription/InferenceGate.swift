import Foundation

/// One speech inference at a time, app-wide.
///
/// FluidAudio recycles MLMultiArrays through one global cache shared by every
/// ASR engine instance, and returning an array zeroes memory another in-flight
/// prediction may still read (observed as libmalloc free-block corruption).
/// Dictation passes, stream finishes, and meeting window processing all take
/// turns through this gate.
///
/// FIFO handoff via continuations, deliberately not a polling loop: value
/// futures throw immediately for a cancelled awaiter, and a `while`/`try?`
/// retry then spins hot enough to starve the cooperative pool and livelock
/// the pipeline (seen in the field as a dictation stuck on "Transcribing").
/// Continuations sit out cancellation, so a cancelled caller simply waits its
/// turn and finishes quietly.
actor InferenceGate {
    static let shared = InferenceGate()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty {
                busy = false
            } else {
                // Hand the gate straight to the next waiter.
                waiters.removeFirst().resume()
            }
        }
        return try await body()
    }
}
