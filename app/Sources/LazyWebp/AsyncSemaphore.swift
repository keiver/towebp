import Foundation

actor AsyncSemaphore {
    private let limit: Int
    private var count: Int = 0
    private var nextWaiterID: UInt64 = 0
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancelledIDs: Set<UInt64> = []

    init(limit: Int) {
        self.limit = limit
    }

    /// Returns `true` if the semaphore was acquired, `false` if cancelled while waiting.
    func wait() async -> Bool {
        if count < limit {
            count += 1
            return true
        }
        let id = nextWaiterID
        nextWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        if cancelledIDs.remove(id) != nil {
            return false
        }
        return true
    }

    private func cancelWaiter(id: UInt64) {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: idx)
            cancelledIDs.insert(id)
            waiter.continuation.resume()
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()
        } else {
            count -= 1
        }
    }
}
