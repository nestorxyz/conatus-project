// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

public enum LocalBindingJournalError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidLeaseDuration
    case workspaceDirectoryRequired
    case workspaceAlreadyRegistered
    case workspacePathAlreadyRegistered
    case workspaceNotRegistered
    case workspaceMismatch
    case leaseBusy
    case staleLease
    case idempotencyConflict
    case bindingAlreadyReady
    case bindingNotReady
    case receiptNotFound
    case receiptKindMismatch
    case providerReferenceConflict
    case journalCreationFailed
    case unsupportedSchemaVersion
    case journalCorrupt
}

public enum LocalWorkspaceState: String, Codable, Equatable, Sendable {
    case available
}

public struct LocalWorkspaceRegistration: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let state: LocalWorkspaceState
}

public struct WriterLease: Codable, Equatable, Sendable {
    public let taskId: String
    public let holderId: String
    public let fenceToken: Int64
    public let expiresAt: Date
}

public enum BindingOperation: String, Codable, Equatable, Sendable {
    case create
    case resume
}

public enum ReceiptState: String, Codable, Equatable, Sendable {
    case prepared
    case committed
}

public struct BindingReceipt: Codable, Equatable, Sendable {
    public let receiptId: String
    public let bindingId: String
    public let taskId: String
    public let workspaceId: String
    public let operation: BindingOperation
    public let state: ReceiptState
    public let preparedFenceToken: Int64
}

public enum RedactedBindingState: String, Codable, Equatable, Sendable {
    case ready
}

public struct RedactedBindingSnapshot: Codable, Equatable, Sendable {
    public let bindingId: String
    public let taskId: String
    public let workspaceId: String
    public let state: RedactedBindingState
    public let hasProviderReference: Bool
}

public enum BindingReconciliation: Codable, Equatable, Sendable {
    case unbound
    case createPending(bindingId: String, receiptId: String?)
    case resumeReady(bindingId: String)
}

public final class LocalBindingJournal: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let databaseURL: URL
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard databaseURL.isFileURL else { throw LocalBindingJournalError.workspaceDirectoryRequired }
        self.databaseURL = databaseURL
        self.now = now
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            guard FileManager.default.createFile(
                atPath: databaseURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw LocalBindingJournalError.journalCreationFailed
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        database = try SQLiteDatabase(url: databaseURL)
        let schemaVersion = try database.userVersion()
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw LocalBindingJournalError.unsupportedSchemaVersion
        }
        try database.executeSchema(Self.schema)
        if schemaVersion == 0 {
            try database.setUserVersion(Self.currentSchemaVersion)
        }
        try secureJournalFiles()
    }

    public func registerWorkspace(workspaceId: String, directoryURL: URL) throws -> LocalWorkspaceRegistration {
        try requireIdentifier(workspaceId)
        let canonicalURL = try canonicalDirectory(directoryURL)
        let registration = try database.transaction { database in
            if let existing = try database.query(
                "SELECT canonical_path FROM workspace_bindings WHERE workspace_id = ?",
                bindings: [.text(workspaceId)]
            ).first {
                guard existing["canonical_path"] == canonicalURL.path else {
                    throw LocalBindingJournalError.workspaceAlreadyRegistered
                }
                return LocalWorkspaceRegistration(workspaceId: workspaceId, state: .available)
            }
            let pathOwner = try database.query(
                "SELECT workspace_id FROM workspace_bindings WHERE canonical_path = ?",
                bindings: [.text(canonicalURL.path)]
            ).first
            guard pathOwner == nil else { throw LocalBindingJournalError.workspacePathAlreadyRegistered }
            try database.execute(
                "INSERT INTO workspace_bindings (workspace_id, canonical_path, registered_at) VALUES (?, ?, ?)",
                bindings: [.text(workspaceId), .text(canonicalURL.path), .double(now().timeIntervalSince1970)]
            )
            return LocalWorkspaceRegistration(workspaceId: workspaceId, state: .available)
        }
        try secureJournalFiles()
        return registration
    }

    public func acquireWriterLease(
        taskId: String,
        holderId: String,
        duration: TimeInterval
    ) throws -> WriterLease {
        try requireIdentifier(taskId)
        try requireIdentifier(holderId)
        guard duration > 0 else { throw LocalBindingJournalError.invalidLeaseDuration }
        let acquired = try database.transaction { database in
            let currentTime = now()
            let existing = try database.query(
                "SELECT holder_id, fence_token, expires_at FROM writer_leases WHERE task_id = ?",
                bindings: [.text(taskId)]
            ).first
            if let existing,
               Double(existing["expires_at"] ?? "") ?? 0 > currentTime.timeIntervalSince1970,
               existing["holder_id"] != holderId
            {
                throw LocalBindingJournalError.leaseBusy
            }
            let nextFence = (Int64(existing?["fence_token"] ?? "") ?? 0) + 1
            let expiresAt = currentTime.addingTimeInterval(duration)
            try database.execute(
                """
                INSERT INTO writer_leases (task_id, holder_id, fence_token, expires_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                  holder_id = excluded.holder_id,
                  fence_token = excluded.fence_token,
                  expires_at = excluded.expires_at
                """,
                bindings: [
                    .text(taskId), .text(holderId), .integer(nextFence),
                    .double(expiresAt.timeIntervalSince1970),
                ]
            )
            return WriterLease(
                taskId: taskId,
                holderId: holderId,
                fenceToken: nextFence,
                expiresAt: expiresAt
            )
        }
        try secureJournalFiles()
        return acquired
    }

    public func releaseWriterLease(_ lease: WriterLease) throws {
        try database.transaction { database in
            try validate(lease: lease, database: database)
            try database.execute(
                """
                UPDATE writer_leases SET expires_at = ?
                WHERE task_id = ? AND holder_id = ? AND fence_token = ?
                """,
                bindings: [
                    .double(now().timeIntervalSince1970), .text(lease.taskId),
                    .text(lease.holderId), .integer(lease.fenceToken),
                ]
            )
        }
    }

    public func prepareCreate(
        taskId: String,
        workspaceId: String,
        idempotencyKey: String,
        lease: WriterLease
    ) throws -> BindingReceipt {
        try prepare(
            operation: .create,
            taskId: taskId,
            workspaceId: workspaceId,
            idempotencyKey: idempotencyKey,
            lease: lease
        )
    }

    public func prepareResume(
        taskId: String,
        workspaceId: String,
        idempotencyKey: String,
        lease: WriterLease
    ) throws -> BindingReceipt {
        try prepare(
            operation: .resume,
            taskId: taskId,
            workspaceId: workspaceId,
            idempotencyKey: idempotencyKey,
            lease: lease
        )
    }

    public func commitCreate(
        receiptId: String,
        providerThreadId: String,
        lease: WriterLease
    ) throws -> RedactedBindingSnapshot {
        try requireIdentifier(providerThreadId)
        let snapshot = try database.transaction { database in
            try validate(lease: lease, database: database)
            let receipt = try loadReceipt(receiptId: receiptId, database: database)
            guard receipt.operation == .create else { throw LocalBindingJournalError.receiptKindMismatch }
            guard receipt.taskId == lease.taskId else { throw LocalBindingJournalError.staleLease }
            let binding = try loadBinding(bindingId: receipt.bindingId, database: database)
            if let existingProviderReference = binding.providerThreadId,
               existingProviderReference != providerThreadId
            {
                throw LocalBindingJournalError.providerReferenceConflict
            }
            if binding.providerThreadId == nil {
                try database.execute(
                    """
                    UPDATE codex_bindings
                    SET provider_thread_id = ?, state = 'ready', updated_at = ?
                    WHERE binding_id = ?
                    """,
                    bindings: [
                        .text(providerThreadId), .double(now().timeIntervalSince1970),
                        .text(receipt.bindingId),
                    ]
                )
            }
            try commitReceipt(receiptId: receipt.receiptId, database: database)
            return RedactedBindingSnapshot(
                bindingId: receipt.bindingId,
                taskId: receipt.taskId,
                workspaceId: receipt.workspaceId,
                state: .ready,
                hasProviderReference: true
            )
        }
        try secureJournalFiles()
        return snapshot
    }

    public func commitResume(
        receiptId: String,
        lease: WriterLease
    ) throws -> RedactedBindingSnapshot {
        let snapshot = try database.transaction { database in
            try validate(lease: lease, database: database)
            let receipt = try loadReceipt(receiptId: receiptId, database: database)
            guard receipt.operation == .resume else { throw LocalBindingJournalError.receiptKindMismatch }
            guard receipt.taskId == lease.taskId else { throw LocalBindingJournalError.staleLease }
            let binding = try loadBinding(bindingId: receipt.bindingId, database: database)
            guard binding.providerThreadId != nil else { throw LocalBindingJournalError.bindingNotReady }
            try commitReceipt(receiptId: receipt.receiptId, database: database)
            return RedactedBindingSnapshot(
                bindingId: receipt.bindingId,
                taskId: receipt.taskId,
                workspaceId: receipt.workspaceId,
                state: .ready,
                hasProviderReference: true
            )
        }
        try secureJournalFiles()
        return snapshot
    }

    public func reconcile(taskId: String) throws -> BindingReconciliation {
        try requireIdentifier(taskId)
        return try database.transaction { database in
            guard let row = try database.query(
                "SELECT binding_id, provider_thread_id FROM codex_bindings WHERE task_id = ?",
                bindings: [.text(taskId)]
            ).first else {
                return .unbound
            }
            let bindingId = try required(row, "binding_id")
            if row["provider_thread_id"] != nil {
                return .resumeReady(bindingId: bindingId)
            }
            let receiptId = try database.query(
                """
                SELECT receipt_id FROM binding_receipts
                WHERE binding_id = ? AND operation = 'create' AND state = 'prepared'
                ORDER BY created_at, receipt_id LIMIT 1
                """,
                bindings: [.text(bindingId)]
            ).first?["receipt_id"]
            return .createPending(bindingId: bindingId, receiptId: receiptId)
        }
    }

    func resolvedWorkspaceURL(workspaceId: String) throws -> URL {
        try database.transaction { database in
            guard let path = try database.query(
                "SELECT canonical_path FROM workspace_bindings WHERE workspace_id = ?",
                bindings: [.text(workspaceId)]
            ).first?["canonical_path"] else {
                throw LocalBindingJournalError.workspaceNotRegistered
            }
            return try canonicalDirectory(URL(fileURLWithPath: path))
        }
    }

    private func prepare(
        operation: BindingOperation,
        taskId: String,
        workspaceId: String,
        idempotencyKey: String,
        lease: WriterLease
    ) throws -> BindingReceipt {
        try requireIdentifier(taskId)
        try requireIdentifier(workspaceId)
        try requireIdentifier(idempotencyKey)
        guard lease.taskId == taskId else { throw LocalBindingJournalError.staleLease }
        let fingerprint = requestFingerprint(operation: operation, taskId: taskId, workspaceId: workspaceId)
        let receipt = try database.transaction { database in
            try validate(lease: lease, database: database)
            guard try database.query(
                "SELECT 1 FROM workspace_bindings WHERE workspace_id = ?",
                bindings: [.text(workspaceId)]
            ).first != nil else {
                throw LocalBindingJournalError.workspaceNotRegistered
            }
            if let existing = try loadReceipt(idempotencyKey: idempotencyKey, database: database) {
                guard existing.requestFingerprint == fingerprint else {
                    throw LocalBindingJournalError.idempotencyConflict
                }
                return existing.receipt
            }

            let binding = try loadBinding(taskId: taskId, database: database)
            let bindingId: String
            if let binding {
                guard binding.workspaceId == workspaceId else { throw LocalBindingJournalError.workspaceMismatch }
                if operation == .create, binding.providerThreadId != nil {
                    throw LocalBindingJournalError.bindingAlreadyReady
                }
                if operation == .resume, binding.providerThreadId == nil {
                    throw LocalBindingJournalError.bindingNotReady
                }
                bindingId = binding.bindingId
                if operation == .create,
                   let pending = try loadPendingCreate(bindingId: bindingId, database: database)
                {
                    return pending
                }
            } else {
                guard operation == .create else { throw LocalBindingJournalError.bindingNotReady }
                bindingId = UUID().uuidString.lowercased()
                let timestamp = now().timeIntervalSince1970
                try database.execute(
                    """
                    INSERT INTO codex_bindings
                      (binding_id, task_id, workspace_id, state, created_at, updated_at)
                    VALUES (?, ?, ?, 'awaiting_provider', ?, ?)
                    """,
                    bindings: [
                        .text(bindingId), .text(taskId), .text(workspaceId),
                        .double(timestamp), .double(timestamp),
                    ]
                )
            }
            return try insertReceipt(
                operation: operation,
                taskId: taskId,
                workspaceId: workspaceId,
                bindingId: bindingId,
                idempotencyKey: idempotencyKey,
                requestFingerprint: fingerprint,
                fenceToken: lease.fenceToken,
                database: database
            )
        }
        try secureJournalFiles()
        return receipt
    }

    private func validate(lease: WriterLease, database: SQLiteDatabase) throws {
        guard let row = try database.query(
            "SELECT holder_id, fence_token, expires_at FROM writer_leases WHERE task_id = ?",
            bindings: [.text(lease.taskId)]
        ).first,
        row["holder_id"] == lease.holderId,
        Int64(row["fence_token"] ?? "") == lease.fenceToken,
        Double(row["expires_at"] ?? "") ?? 0 > now().timeIntervalSince1970
        else {
            throw LocalBindingJournalError.staleLease
        }
    }

    private func insertReceipt(
        operation: BindingOperation,
        taskId: String,
        workspaceId: String,
        bindingId: String,
        idempotencyKey: String,
        requestFingerprint: String,
        fenceToken: Int64,
        database: SQLiteDatabase
    ) throws -> BindingReceipt {
        let receiptId = UUID().uuidString.lowercased()
        try database.execute(
            """
            INSERT INTO binding_receipts
              (receipt_id, idempotency_key, request_fingerprint, operation, binding_id,
               task_id, workspace_id, prepared_fence_token, state, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'prepared', ?)
            """,
            bindings: [
                .text(receiptId), .text(idempotencyKey), .text(requestFingerprint),
                .text(operation.rawValue), .text(bindingId), .text(taskId),
                .text(workspaceId), .integer(fenceToken), .double(now().timeIntervalSince1970),
            ]
        )
        return BindingReceipt(
            receiptId: receiptId,
            bindingId: bindingId,
            taskId: taskId,
            workspaceId: workspaceId,
            operation: operation,
            state: .prepared,
            preparedFenceToken: fenceToken
        )
    }

    private func loadReceipt(
        idempotencyKey: String,
        database: SQLiteDatabase
    ) throws -> (receipt: BindingReceipt, requestFingerprint: String)? {
        guard let row = try database.query(
            """
            SELECT receipt_id, binding_id, task_id, workspace_id, operation, state,
                   prepared_fence_token, request_fingerprint
            FROM binding_receipts WHERE idempotency_key = ?
            """,
            bindings: [.text(idempotencyKey)]
        ).first else { return nil }
        return (try mapReceipt(row), try required(row, "request_fingerprint"))
    }

    private func loadReceipt(receiptId: String, database: SQLiteDatabase) throws -> BindingReceipt {
        guard let row = try database.query(
            """
            SELECT receipt_id, binding_id, task_id, workspace_id, operation, state,
                   prepared_fence_token
            FROM binding_receipts WHERE receipt_id = ?
            """,
            bindings: [.text(receiptId)]
        ).first else {
            throw LocalBindingJournalError.receiptNotFound
        }
        return try mapReceipt(row)
    }

    private func loadPendingCreate(bindingId: String, database: SQLiteDatabase) throws -> BindingReceipt? {
        guard let row = try database.query(
            """
            SELECT receipt_id, binding_id, task_id, workspace_id, operation, state,
                   prepared_fence_token
            FROM binding_receipts
            WHERE binding_id = ? AND operation = 'create' AND state = 'prepared'
            ORDER BY created_at, receipt_id LIMIT 1
            """,
            bindings: [.text(bindingId)]
        ).first else { return nil }
        return try mapReceipt(row)
    }

    private func loadBinding(taskId: String, database: SQLiteDatabase) throws -> LocalBinding? {
        guard let row = try database.query(
            """
            SELECT binding_id, task_id, workspace_id, provider_thread_id
            FROM codex_bindings WHERE task_id = ?
            """,
            bindings: [.text(taskId)]
        ).first else { return nil }
        return try mapBinding(row)
    }

    private func loadBinding(bindingId: String, database: SQLiteDatabase) throws -> LocalBinding {
        guard let row = try database.query(
            """
            SELECT binding_id, task_id, workspace_id, provider_thread_id
            FROM codex_bindings WHERE binding_id = ?
            """,
            bindings: [.text(bindingId)]
        ).first else {
            throw LocalBindingJournalError.bindingNotReady
        }
        return try mapBinding(row)
    }

    private func commitReceipt(receiptId: String, database: SQLiteDatabase) throws {
        try database.execute(
            """
            UPDATE binding_receipts SET state = 'committed', committed_at = ?
            WHERE receipt_id = ? AND state = 'prepared'
            """,
            bindings: [.double(now().timeIntervalSince1970), .text(receiptId)]
        )
    }

    private func mapReceipt(_ row: [String: String]) throws -> BindingReceipt {
        guard let operation = BindingOperation(rawValue: try required(row, "operation")),
              let state = ReceiptState(rawValue: try required(row, "state")),
              let fenceToken = Int64(try required(row, "prepared_fence_token"))
        else {
            throw LocalBindingJournalError.journalCorrupt
        }
        return BindingReceipt(
            receiptId: try required(row, "receipt_id"),
            bindingId: try required(row, "binding_id"),
            taskId: try required(row, "task_id"),
            workspaceId: try required(row, "workspace_id"),
            operation: operation,
            state: state,
            preparedFenceToken: fenceToken
        )
    }

    private func mapBinding(_ row: [String: String]) throws -> LocalBinding {
        LocalBinding(
            bindingId: try required(row, "binding_id"),
            taskId: try required(row, "task_id"),
            workspaceId: try required(row, "workspace_id"),
            providerThreadId: row["provider_thread_id"]
        )
    }

    private func canonicalDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw LocalBindingJournalError.workspaceDirectoryRequired
        }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw LocalBindingJournalError.workspaceDirectoryRequired
        }
        return canonical
    }

    private func secureJournalFiles() throws {
        for url in [databaseURL, URL(fileURLWithPath: databaseURL.path + "-wal"), URL(fileURLWithPath: databaseURL.path + "-shm")]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func requireIdentifier(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw LocalBindingJournalError.invalidIdentifier
        }
    }

    private func requestFingerprint(
        operation: BindingOperation,
        taskId: String,
        workspaceId: String
    ) -> String {
        let bytes = SHA256.hash(data: Data("\(operation.rawValue)\0\(taskId)\0\(workspaceId)".utf8))
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func required(_ row: [String: String], _ column: String) throws -> String {
        guard let value = row[column] else { throw LocalBindingJournalError.journalCorrupt }
        return value
    }

    private struct LocalBinding {
        let bindingId: String
        let taskId: String
        let workspaceId: String
        let providerThreadId: String?
    }

    private static let currentSchemaVersion = 1

    private static let schema = """
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = FULL;
    CREATE TABLE IF NOT EXISTS workspace_bindings (
      workspace_id TEXT PRIMARY KEY,
      canonical_path TEXT NOT NULL UNIQUE,
      registered_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS codex_bindings (
      binding_id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL UNIQUE,
      workspace_id TEXT NOT NULL,
      provider_thread_id TEXT UNIQUE,
      state TEXT NOT NULL CHECK (state IN ('awaiting_provider', 'ready')),
      created_at REAL NOT NULL,
      updated_at REAL NOT NULL,
      FOREIGN KEY (workspace_id) REFERENCES workspace_bindings(workspace_id)
    );

    CREATE TABLE IF NOT EXISTS writer_leases (
      task_id TEXT PRIMARY KEY,
      holder_id TEXT NOT NULL,
      fence_token INTEGER NOT NULL CHECK (fence_token > 0),
      expires_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS binding_receipts (
      receipt_id TEXT PRIMARY KEY,
      idempotency_key TEXT NOT NULL UNIQUE,
      request_fingerprint TEXT NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('create', 'resume')),
      binding_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      workspace_id TEXT NOT NULL,
      prepared_fence_token INTEGER NOT NULL CHECK (prepared_fence_token > 0),
      state TEXT NOT NULL CHECK (state IN ('prepared', 'committed')),
      created_at REAL NOT NULL,
      committed_at REAL,
      FOREIGN KEY (binding_id) REFERENCES codex_bindings(binding_id),
      CHECK ((state = 'prepared' AND committed_at IS NULL)
        OR (state = 'committed' AND committed_at IS NOT NULL))
    );

    CREATE INDEX IF NOT EXISTS binding_receipt_lookup_idx
      ON binding_receipts(binding_id, operation, state, created_at, receipt_id);
    """
}
