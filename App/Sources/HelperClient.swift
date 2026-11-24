import Foundation

/// The app's line to the helper. Every answer comes back on the main thread, exactly once.
final class HelperClient {
    private var connection: NSXPCConnection?

    private func open() -> NSXPCConnection {
        if let connection { return connection }
        let new = NSXPCConnection(machServiceName: HelperInfo.label, options: .privileged)
        new.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        // The Mac itself makes sure the other end is the real helper.
        new.setCodeSigningRequirement(HelperInfo.helperRequirement)
        new.invalidationHandler = { [weak self, weak new] in
            DispatchQueue.main.async { if self?.connection === new { self?.connection = nil } }
        }
        new.resume()
        connection = new
        return new
    }

    /// Lets go of the line, for example after the helper was installed afresh or removed.
    func reset() {
        connection?.invalidate()
        connection = nil
    }

    /// One answer only: the helper's, or the line's complaint, or silence after a few seconds.
    private final class Once<T> {
        private var done = false
        private let lock = NSLock()
        private let finish: (T) -> Void
        init(_ finish: @escaping (T) -> Void) { self.finish = finish }
        func call(_ value: T) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            guard first else { return }
            DispatchQueue.main.async { self.finish(value) }
        }
    }

    /// The helper's version; nil when it does not answer.
    func version(_ done: @escaping (String?) -> Void) {
        let once = Once(done)
        let helper = open().remoteObjectProxyWithErrorHandler { _ in once.call(nil) } as? FanHelperProtocol
        guard let helper else { once.call(nil); return }
        helper.version { once.call($0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.call(nil) }
    }

    func setSpeeds(_ speeds: [Double], _ done: @escaping (Bool, String) -> Void) {
        let once = Once<(Bool, String)> { done($0.0, $0.1) }
        let helper = open().remoteObjectProxyWithErrorHandler { error in
            once.call((false, "the helper did not answer: \(error.localizedDescription)"))
        } as? FanHelperProtocol
        guard let helper else { once.call((false, "the helper is not there")); return }
        helper.setSpeeds(speeds.map { NSNumber(value: $0) }) { ok, text in once.call((ok, text)) }
        // Unlocking a newer Mac's fans can take a few seconds; after that, silence is a no.
        DispatchQueue.global().asyncAfter(deadline: .now() + 12) { once.call((false, "the helper did not answer in time")) }
    }

    func giveBack(_ done: @escaping (Bool, String) -> Void = { _, _ in }) {
        let once = Once<(Bool, String)> { done($0.0, $0.1) }
        let helper = open().remoteObjectProxyWithErrorHandler { error in
            once.call((false, "the helper did not answer: \(error.localizedDescription)"))
        } as? FanHelperProtocol
        guard let helper else { once.call((false, "the helper is not there")); return }
        helper.giveBack { ok, text in once.call((ok, text)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.call((false, "the helper did not answer in time")) }
    }

    /// For quitting: gives the fans back and waits a moment for the helper's word. Call on the main thread.
    @discardableResult
    func giveBackAndWait(seconds: Double = 2) -> Bool {
        let waiter = DispatchSemaphore(value: 0)
        var fine = false
        let helper = open().remoteObjectProxyWithErrorHandler { _ in waiter.signal() } as? FanHelperProtocol
        guard let helper else { return false }
        helper.giveBack { ok, _ in
            fine = ok
            waiter.signal()
        }
        _ = waiter.wait(timeout: .now() + seconds)
        return fine
    }
}
