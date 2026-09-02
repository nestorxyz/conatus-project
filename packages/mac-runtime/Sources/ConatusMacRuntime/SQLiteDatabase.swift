// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SQLite3

enum SQLiteDatabaseError: Error {
    case open(String)
    case prepare(String)
    case bind(String)
    case step(String)
    case execute(String)
}

enum SQLiteBinding {
    case text(String)
    case integer(Int64)
    case double(Double)
    case null
}

final class SQLiteDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close_v2(database) }
            throw SQLiteDatabaseError.open(message)
        }
        handle = database
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func executeSchema(_ sql: String) throws {
        try withLock {
            try executeRaw(sql)
        }
    }

    func userVersion() throws -> Int {
        try withLock {
            guard let value = try query("PRAGMA user_version").first?["user_version"],
                  let version = Int(value)
            else {
                throw SQLiteDatabaseError.step("SQLite returned an invalid user_version")
            }
            return version
        }
    }

    func setUserVersion(_ version: Int) throws {
        try withLock {
            try executeRaw("PRAGMA user_version = \(version)")
        }
    }

    func transaction<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        try withLock {
            try executeRaw("BEGIN IMMEDIATE")
            do {
                let result = try body(self)
                try executeRaw("COMMIT")
                return result
            } catch {
                try? executeRaw("ROLLBACK")
                throw error
            }
        }
    }

    @discardableResult
    func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteDatabaseError.step(errorMessage)
        }
        return Int(sqlite3_changes(requiredHandle))
    }

    func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw SQLiteDatabaseError.step(errorMessage) }
            var row: [String: String] = [:]
            for index in 0 ..< sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, index) else { continue }
                guard sqlite3_column_type(statement, index) != SQLITE_NULL else { continue }
                if let value = sqlite3_column_text(statement, index) {
                    row[String(cString: name)] = String(cString: value)
                }
            }
            rows.append(row)
        }
    }

    private var requiredHandle: OpaquePointer {
        guard let handle else { preconditionFailure("SQLite database used after close") }
        return handle
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(requiredHandle))
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(requiredHandle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteDatabaseError.prepare(errorMessage)
        }
        do {
            for (offset, binding) in bindings.enumerated() {
                try bind(binding, to: statement, index: Int32(offset + 1))
            }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func bind(_ binding: SQLiteBinding, to statement: OpaquePointer, index: Int32) throws {
        let result: Int32
        switch binding {
        case let .text(value):
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        case let .integer(value):
            result = sqlite3_bind_int64(statement, index, value)
        case let .double(value):
            result = sqlite3_bind_double(statement, index, value)
        case .null:
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw SQLiteDatabaseError.bind(errorMessage) }
    }

    private func executeRaw(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(requiredHandle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(message)
            throw SQLiteDatabaseError.execute(detail)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
