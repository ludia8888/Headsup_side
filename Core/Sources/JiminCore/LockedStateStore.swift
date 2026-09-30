import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// App and DeviceActivity extension must perform read-modify-write under the same lock.
public final class LockedStateStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    @discardableResult public func update<T>(_ mutate: (inout SharedState) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("state.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StoreError.lock }
        defer { _ = flock(fd, LOCK_UN); _ = close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.lock }
        let file = directory.appendingPathComponent("state.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var state: SharedState
        if FileManager.default.fileExists(atPath: file.path) {
            // Never silently reset a corrupt ledger: that could cause extra calls.
            state = try decoder.decode(SharedState.self, from: Data(contentsOf: file))
        } else { state = SharedState() }
        let result = try mutate(&state)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: file, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
        return result
    }

    public func read() throws -> SharedState { try update { $0 } }
    public enum StoreError: Error { case lock }
}
