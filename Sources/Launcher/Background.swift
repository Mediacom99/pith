import Dispatch

/// Runs blocking work (walking folders, rendering icons) on a GCD worker thread and awaits its result.
///
/// Not the main thread, which only handles events and draws. Not `Task.detached` either: Swift's cooperative pool has
/// one thread per core and must never block, and this work blocks on disk and on IconServices.
func runInBackground<T: Sendable>(qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
    }
}
