// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import ConatusVoicePlatform

@MainActor
final class NativeSpeechOutputTests: XCTestCase {
    func testAcknowledgementUsesSeparateImmediateFeedback() {
        let backend = FakeNativeSpeechSynthesizer()
        var acknowledgements = 0
        let output = NativeSpeechOutput(synthesizer: backend) { acknowledgements += 1 }

        output.playAcknowledgement()

        XCTAssertEqual(acknowledgements, 1)
        XCTAssertTrue(backend.spokenTexts.isEmpty)
    }

    func testNormalizesAndAwaitsNativeCompletion() async throws {
        let backend = FakeNativeSpeechSynthesizer()
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})
        let task = Task { try await output.speak("  Work is complete.  ") }
        await Task.yield()

        XCTAssertEqual(backend.spokenTexts, ["Work is complete."])
        XCTAssertFalse(task.isCancelled)
        backend.complete(.finished)
        try await task.value
    }

    func testRejectsEmptyAndOversizedStatusBeforeNativeSpeech() async {
        let backend = FakeNativeSpeechSynthesizer()
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})

        await assertFailure(.invalidStatus) { try await output.speak("  \n ") }
        await assertFailure(.statusTooLong) {
            try await output.speak(String(repeating: "x", count: NativeSpeechOutput.maximumStatusCharacters + 1))
        }
        XCTAssertTrue(backend.spokenTexts.isEmpty)
    }

    func testAllowsOnlyOneActiveUtterance() async throws {
        let backend = FakeNativeSpeechSynthesizer()
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})
        let first = Task { try await output.speak("first") }
        await Task.yield()

        await assertFailure(.alreadySpeaking) { try await output.speak("second") }
        XCTAssertEqual(backend.spokenTexts, ["first"])
        backend.complete(.finished)
        try await first.value
    }

    func testStopCancelsPendingSpeechExactlyOnce() async {
        let backend = FakeNativeSpeechSynthesizer()
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})
        let task = Task { try await output.speak("interrupt me") }
        await Task.yield()

        output.stop()
        backend.complete(.finished)
        output.stop()

        XCTAssertEqual(backend.stopCount, 1)
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeFailureMapsToTypedSafeFailure() async {
        let backend = FakeNativeSpeechSynthesizer()
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})
        let task = Task { try await output.speak("status") }
        await Task.yield()
        backend.complete(.failed)

        await assertTaskFailure(task, expected: .nativeFailure)
    }

    func testNativeStartFailureDoesNotLeaveDriverBusy() async throws {
        let backend = FakeNativeSpeechSynthesizer()
        backend.startError = .nativeFailure
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})

        await assertFailure(.nativeFailure) { try await output.speak("first") }
        backend.startError = nil
        let retry = Task { try await output.speak("retry") }
        await Task.yield()
        backend.complete(.finished)
        try await retry.value
    }

    func testLateCompletionFromCancelledUtteranceCannotFinishReplacement() async throws {
        let backend = FakeNativeSpeechSynthesizer()
        backend.deferStopCompletion = true
        let output = NativeSpeechOutput(synthesizer: backend, acknowledge: {})
        let cancelled = Task { try await output.speak("cancelled") }
        await Task.yield()
        output.stop()

        let replacement = Task { try await output.speak("replacement") }
        await Task.yield()
        backend.completeDeferredStop(.finished)
        XCTAssertEqual(backend.spokenTexts, ["cancelled", "replacement"])

        backend.complete(.finished)
        try await replacement.value
        do {
            try await cancelled.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertFailure(
        _ expected: NativeSpeechOutputError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as NativeSpeechOutputError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertTaskFailure(
        _ task: Task<Void, Error>,
        expected: NativeSpeechOutputError
    ) async {
        do {
            try await task.value
            XCTFail("Expected \(expected)")
        } catch let error as NativeSpeechOutputError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class FakeNativeSpeechSynthesizer: NativeSpeechSynthesizing {
    var spokenTexts: [String] = []
    var stopCount = 0
    var startError: NativeSpeechOutputError?
    var deferStopCompletion = false
    private var completion: (@MainActor @Sendable (NativeSpeechCompletion) -> Void)?
    private var deferredStopCompletion: (@MainActor @Sendable (NativeSpeechCompletion) -> Void)?

    func speak(
        _ text: String,
        completion: @escaping @MainActor @Sendable (NativeSpeechCompletion) -> Void
    ) throws {
        if let startError { throw startError }
        spokenTexts.append(text)
        self.completion = completion
    }

    func stop() {
        stopCount += 1
        if deferStopCompletion {
            deferredStopCompletion = completion
            completion = nil
            return
        }
        complete(.cancelled)
    }

    func complete(_ result: NativeSpeechCompletion) {
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    func completeDeferredStop(_ result: NativeSpeechCompletion) {
        let completion = deferredStopCompletion
        deferredStopCompletion = nil
        completion?(result)
    }
}
