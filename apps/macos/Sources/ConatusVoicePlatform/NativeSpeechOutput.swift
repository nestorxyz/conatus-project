// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import AVFoundation
import ConatusVoice
import Foundation

public enum NativeSpeechOutputError: Error, Equatable, Sendable {
    case alreadySpeaking
    case invalidStatus
    case nativeFailure
    case statusTooLong
}

enum NativeSpeechCompletion: Equatable, Sendable {
    case cancelled
    case failed
    case finished
}

@MainActor
protocol NativeSpeechSynthesizing: AnyObject {
    func speak(
        _ text: String,
        completion: @escaping @MainActor @Sendable (NativeSpeechCompletion) -> Void
    ) throws
    func stop()
}

@MainActor
public final class NativeSpeechOutput: VoiceSpeechControlling {
    public static let maximumStatusCharacters = 1_000

    private let synthesizer: any NativeSpeechSynthesizing
    private let acknowledge: @MainActor () -> Void
    private var activeUtteranceID: UUID?
    private var continuation: CheckedContinuation<Void, Error>?

    public convenience init() {
        self.init(synthesizer: AVSpeechSynthesizerBackend(), acknowledge: { NSSound.beep() })
    }

    init(
        synthesizer: any NativeSpeechSynthesizing,
        acknowledge: @escaping @MainActor () -> Void
    ) {
        self.synthesizer = synthesizer
        self.acknowledge = acknowledge
    }

    public func playAcknowledgement() {
        acknowledge()
    }

    public func speak(_ status: String) async throws {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NativeSpeechOutputError.invalidStatus }
        guard normalized.count <= Self.maximumStatusCharacters else {
            throw NativeSpeechOutputError.statusTooLong
        }
        guard continuation == nil else { throw NativeSpeechOutputError.alreadySpeaking }
        try Task.checkCancellation()

        let utteranceID = UUID()
        activeUtteranceID = utteranceID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                do {
                    try synthesizer.speak(normalized) { [weak self] completion in
                        self?.finish(utteranceID: utteranceID, completion: completion)
                    }
                } catch {
                    finish(utteranceID: utteranceID, completion: .failed)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    public func stop() {
        guard let activeUtteranceID else { return }
        synthesizer.stop()
        finish(utteranceID: activeUtteranceID, completion: .cancelled)
    }

    private func finish(utteranceID: UUID, completion: NativeSpeechCompletion) {
        guard activeUtteranceID == utteranceID, let continuation else { return }
        activeUtteranceID = nil
        self.continuation = nil
        switch completion {
        case .finished:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        case .failed:
            continuation.resume(throwing: NativeSpeechOutputError.nativeFailure)
        }
    }
}

@MainActor
private final class AVSpeechSynthesizerBackend: NSObject, NativeSpeechSynthesizing,
    @preconcurrency AVSpeechSynthesizerDelegate
{
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var completion: (@MainActor @Sendable (NativeSpeechCompletion) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ text: String,
        completion: @escaping @MainActor @Sendable (NativeSpeechCompletion) -> Void
    ) throws {
        guard self.completion == nil else { throw NativeSpeechOutputError.alreadySpeaking }
        let utterance = AVSpeechUtterance(string: text)
        activeUtterance = utterance
        self.completion = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        guard let activeUtterance else { return }
        _ = synthesizer.stopSpeaking(at: .immediate)
        complete(.cancelled, for: activeUtterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(.finished, for: utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(.cancelled, for: utterance)
    }

    private func complete(_ result: NativeSpeechCompletion, for utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        let completion = self.completion
        activeUtterance = nil
        self.completion = nil
        completion?(result)
    }
}
