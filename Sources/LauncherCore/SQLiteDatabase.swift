import Foundation
import SQLite3

/// A SQLite connection with prepared statements: the few calls the clipboard store needs. Not thread-safe: its owner
/// uses it from one serial queue.
final class SQLiteDatabase {
    typealias Failure = ClipboardStore.Failure

    enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
        case null
    }

    private let handle: OpaquePointer

    init(path: String) throws(Failure) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close_v2(handle)
            throw Failure(description: "couldn't open \(path): \(message)")
        }
        self.handle = handle
        // Another program writing to the history (decision 73) holds the lock for a moment: wait for it, on the
        // store's queue, rather than lose the copy.
        sqlite3_busy_timeout(handle, 2_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that take no arguments.
    func execute(_ sql: String) throws(Failure) {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? lastError.description
            sqlite3_free(message)
            throw Failure(description: text)
        }
    }

    func prepare(_ sql: String) throws(Failure) -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw lastError }
        return Statement(statement, database: self)
    }

    /// Runs `work` in one transaction: all of it lands, or none of it does.
    func transaction<T>(_ work: () throws(Failure) -> T) throws(Failure) -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertedRow: Int64 { sqlite3_last_insert_rowid(handle) }

    var lastError: Failure { Failure(description: String(cString: sqlite3_errmsg(handle))) }

    /// A prepared statement, reset and bound again for each use.
    final class Statement {
        private let handle: OpaquePointer
        private unowned let database: SQLiteDatabase

        fileprivate init(_ handle: OpaquePointer, database: SQLiteDatabase) {
            self.handle = handle
            self.database = database
        }

        deinit {
            sqlite3_finalize(handle)
        }

        /// Resets the statement and binds `arguments` to its `?` placeholders, in order.
        @discardableResult
        func bind(_ arguments: [Value]) throws(Failure) -> Statement {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
            // Tells SQLite to copy what's bound, since Swift's buffers don't outlive the call.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (offset, value) in arguments.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case .integer(let number): status = sqlite3_bind_int64(handle, index, number)
                case .real(let number): status = sqlite3_bind_double(handle, index, number)
                case .text(let text):
                    status = sqlite3_bind_text(handle, index, text, Int32(text.utf8.count), transient)
                case .blob(let data):
                    status = data.withUnsafeBytes { bytes in
                        // An empty buffer has no address, which SQLite would store as NULL.
                        guard let base = bytes.baseAddress else { return sqlite3_bind_zeroblob(handle, index, 0) }
                        return sqlite3_bind_blob(handle, index, base, Int32(bytes.count), transient)
                    }
                case .null: status = sqlite3_bind_null(handle, index)
                }
                guard status == SQLITE_OK else { throw database.lastError }
            }
            return self
        }

        /// Steps once: true when a row is ready to read, false when the statement is done.
        func step() throws(Failure) -> Bool {
            switch sqlite3_step(handle) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw database.lastError
            }
        }

        /// Ends a read early, so the statement holds no lock while others run.
        func reset() {
            sqlite3_reset(handle)
        }

        /// Steps to the end, for statements that return no rows.
        func run(_ arguments: [Value] = []) throws(Failure) {
            try bind(arguments)
            while try step() {}
        }

        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }

        func real(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }

        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }

        func text(_ column: Int32) -> String {
            guard let bytes = sqlite3_column_text(handle, column) else { return "" }
            let count = Int(sqlite3_column_bytes(handle, column))
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        }

        func blob(_ column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(handle, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
        }
    }
}
