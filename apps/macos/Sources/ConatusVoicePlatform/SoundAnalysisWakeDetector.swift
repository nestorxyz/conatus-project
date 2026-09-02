// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import ConatusVoice
import CoreMedia
import CoreML
import Foundation
import SoundAnalysis

public enum SoundAnalysisWakeError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResult
    case analysisFailed
    case alreadyFinished
}

public enum SoundAnalysisScoreMapper {
    public static func map(
        identifier: String,
        confidence: Double,
        expectedIdentifier: String,
        startSeconds: Double,
        durationSeconds: Double,
        sampleRate: Int
    ) throws -> WakeScoreObservation? {
        guard identifier == expectedIdentifier else { return nil }
        guard
            confidence.isFinite,
            (0 ... 1).contains(confidence),
            startSeconds.isFinite,
            startSeconds >= 0,
            durationSeconds.isFinite,
            durationSeconds > 0,
            sampleRate > 0
        else {
            throw SoundAnalysisWakeError.invalidResult
        }
        let startValue = (startSeconds * Double(sampleRate)).rounded(.down)
        let endValue = ((startSeconds + durationSeconds) * Double(sampleRate)).rounded(.up)
        guard
            startValue <= Double(Int64.max),
            endValue <= Double(Int64.max),
            endValue > startValue
        else {
            throw SoundAnalysisWakeError.invalidResult
        }
        let range = try AudioFrameRange(start: Int64(startValue), end: Int64(endValue))
        return try WakeScoreObservation(score: confidence, range: range)
    }
}

public final class SoundAnalysisWakeDetector: NSObject, SNResultsObserving, @unchecked Sendable {
    public typealias ScoreHandler = @Sendable (Result<WakeScoreObservation, SoundAnalysisWakeError>) -> Void

    private final class AnalysisContext: @unchecked Sendable {
        let analyzer: SNAudioStreamAnalyzer
        let request: SNClassifySoundRequest

        init(analyzer: SNAudioStreamAnalyzer, request: SNClassifySoundRequest) {
            self.analyzer = analyzer
            self.request = request
        }
    }

    private let context: AnalysisContext
    private let expectedIdentifier: String
    private let sampleRate: Int
    private let handler: ScoreHandler
    private let queue = DispatchQueue(label: "com.conatus.voice.sound-analysis", qos: .userInitiated)
    private let finishLock = NSLock()
    private var finished = false

    public init(
        model: MLModel,
        audioFormat: AVAudioFormat,
        expectedIdentifier: String,
        overlapFactor: Double = 0.5,
        handler: @escaping ScoreHandler
    ) throws {
        guard
            !expectedIdentifier.isEmpty,
            overlapFactor.isFinite,
            (0 ..< 1).contains(overlapFactor),
            audioFormat.sampleRate > 0
        else {
            throw SoundAnalysisWakeError.invalidConfiguration
        }
        let roundedSampleRate = Int(audioFormat.sampleRate.rounded())
        guard abs(audioFormat.sampleRate - Double(roundedSampleRate)) < 0.001 else {
            throw SoundAnalysisWakeError.invalidConfiguration
        }
        let analyzer = SNAudioStreamAnalyzer(format: audioFormat)
        let request = try SNClassifySoundRequest(mlModel: model)
        request.overlapFactor = overlapFactor
        context = AnalysisContext(analyzer: analyzer, request: request)
        self.expectedIdentifier = expectedIdentifier
        sampleRate = roundedSampleRate
        self.handler = handler
        super.init()
        try context.analyzer.add(context.request, withObserver: self)
    }

    public func analyze(_ frame: CopiedMicrophoneFrame) throws {
        finishLock.lock()
        guard !finished else {
            finishLock.unlock()
            throw SoundAnalysisWakeError.alreadyFinished
        }
        queue.async { [context] in
            context.analyzer.analyze(
                frame.pcmBuffer,
                atAudioFramePosition: AVAudioFramePosition(frame.audioChunk.startFrame)
            )
        }
        finishLock.unlock()
    }

    public func finish() {
        finishLock.lock()
        guard !finished else {
            finishLock.unlock()
            return
        }
        finished = true
        queue.async { [context] in
            context.analyzer.completeAnalysis()
            context.analyzer.remove(context.request)
        }
        finishLock.unlock()
    }

    public func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let classifications = result as? SNClassificationResult else { return }
        guard let classification = classifications.classification(forIdentifier: expectedIdentifier) else { return }
        do {
            let start = CMTimeGetSeconds(classifications.timeRange.start)
            let duration = CMTimeGetSeconds(classifications.timeRange.duration)
            if let observation = try SoundAnalysisScoreMapper.map(
                identifier: classification.identifier,
                confidence: classification.confidence,
                expectedIdentifier: expectedIdentifier,
                startSeconds: start,
                durationSeconds: duration,
                sampleRate: sampleRate
            ) {
                handler(.success(observation))
            }
        } catch {
            handler(.failure(.invalidResult))
        }
    }

    public func request(_ request: any SNRequest, didFailWithError error: any Error) {
        handler(.failure(.analysisFailed))
    }

    public func requestDidComplete(_ request: any SNRequest) {}
}
