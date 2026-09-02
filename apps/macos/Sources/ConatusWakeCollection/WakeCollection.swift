// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum WakeConsentUse: String, Codable, CaseIterable, Sendable {
  case trainWakeModel = "train_wake_model"
  case evaluateWakeModel = "evaluate_wake_model"
  case distributeDerivedModel = "distribute_derived_model"
}

private struct WakeConsentReceipt: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let consentVersion: String
  let participantID: String
  let controllerReference: String
  let consentedAt: String
  let rawAudioDeletionAt: String
  let modelReleaseCutoffAt: String
  let withdrawalContactReference: String
  let permittedUses: [WakeConsentUse]
  let adultConfirmed: Bool
  let noThirdPartyVoicesConfirmed: Bool
  let rawAudioPublicationAllowed: Bool
  let operatorApprovalReference: String
}

public struct ValidatedWakeConsent: Sendable {
  fileprivate init() {}
}

public enum WakeCollectionLabel: String, Codable, Sendable {
  case wake = "hey_conatus"
  case background
}

public struct WakeCollectionTake: Codable, Equatable, Sendable {
  public let takeID: String
  public let label: WakeCollectionLabel
  public let prompt: String
  public let pronunciationTag: String
  public let environmentTag: String
  public let distanceCentimeters: Int

  public init(
    takeID: String,
    label: WakeCollectionLabel,
    prompt: String,
    pronunciationTag: String,
    environmentTag: String,
    distanceCentimeters: Int
  ) {
    self.takeID = takeID
    self.label = label
    self.prompt = prompt
    self.pronunciationTag = pronunciationTag
    self.environmentTag = environmentTag
    self.distanceCentimeters = distanceCentimeters
  }
}

public struct WakeRecordedTakeEvidence: Codable, Equatable, Sendable {
  public let takeID: String
  public let sha256: String
  public let sampleRate: Int
  public let channelCount: Int
  public let durationMilliseconds: Int

  public init(
    takeID: String,
    sha256: String,
    sampleRate: Int,
    channelCount: Int,
    durationMilliseconds: Int
  ) {
    self.takeID = takeID
    self.sha256 = sha256
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.durationMilliseconds = durationMilliseconds
  }
}

public enum WakeCollectionState: String, Codable, Sendable {
  case awaitingConsent
  case ready
  case recording
  case reviewing
  case completed
}

public enum WakeCollectionDirective: Equatable, Sendable {
  case startTemporaryRecording(takeID: String)
  case discardTemporaryRecording(takeID: String)
  case retainAcceptedRecording(takeID: String)
}

public struct WakeCollectionStatus: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let state: WakeCollectionState
  public let completedTakeCount: Int
  public let totalTakeCount: Int
}

public enum WakeCollectionError: Error, Equatable, Sendable {
  case malformedConsent
  case unknownField
  case unsupportedConsent
  case invalidConsent
  case invalidPlan
  case invalidState
  case takeMismatch
  case invalidRecordingEvidence
}

public enum WakeConsentValidator {
  private static let keys = Set([
    "schemaVersion", "consentVersion", "participantID", "controllerReference", "consentedAt",
    "rawAudioDeletionAt", "modelReleaseCutoffAt", "withdrawalContactReference",
    "permittedUses", "adultConfirmed",
    "noThirdPartyVoicesConfirmed", "rawAudioPublicationAllowed",
    "operatorApprovalReference",
  ])

  public static func decodeAndValidate(_ data: Data) throws -> ValidatedWakeConsent {
    let raw: Any
    do {
      raw = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw WakeCollectionError.malformedConsent
    }
    guard let object = raw as? [String: Any], Set(object.keys) == keys else {
      throw WakeCollectionError.unknownField
    }
    let receipt: WakeConsentReceipt
    do {
      receipt = try JSONDecoder().decode(WakeConsentReceipt.self, from: data)
    } catch {
      throw WakeCollectionError.malformedConsent
    }
    guard receipt.schemaVersion == 1, receipt.consentVersion == "conatus-wake-consent-v1" else {
      throw WakeCollectionError.unsupportedConsent
    }
    let requiredUses = Set(WakeConsentUse.allCases)
    let uses = Set(receipt.permittedUses)
    let formatter = ISO8601DateFormatter()
    guard
      opaque(receipt.participantID),
      opaque(receipt.controllerReference),
      opaque(receipt.withdrawalContactReference),
      opaque(receipt.operatorApprovalReference),
      let consentedAt = formatter.date(from: receipt.consentedAt),
      let deletionAt = formatter.date(from: receipt.rawAudioDeletionAt),
      let releaseCutoffAt = formatter.date(from: receipt.modelReleaseCutoffAt),
      deletionAt > consentedAt,
      releaseCutoffAt > consentedAt,
      uses == requiredUses,
      uses.count == receipt.permittedUses.count,
      receipt.adultConfirmed,
      receipt.noThirdPartyVoicesConfirmed,
      !receipt.rawAudioPublicationAllowed
    else {
      throw WakeCollectionError.invalidConsent
    }
    return ValidatedWakeConsent()
  }

  private static func opaque(_ value: String) -> Bool {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    return (8...100).contains(value.count)
      && value.unicodeScalars.allSatisfy(allowed.contains)
  }
}

public struct WakeCollectionSession: Sendable {
  private let plan: [WakeCollectionTake]
  private var consent: ValidatedWakeConsent?
  private var nextIndex = 0
  private var pendingEvidence: WakeRecordedTakeEvidence?

  public private(set) var state: WakeCollectionState = .awaitingConsent

  public init(plan: [WakeCollectionTake]) throws {
    guard
      !plan.isEmpty,
      Set(plan.map(\.takeID)).count == plan.count,
      plan.allSatisfy({ Self.valid($0) })
    else {
      throw WakeCollectionError.invalidPlan
    }
    self.plan = plan
  }

  public mutating func applyConsent(_ validatedConsent: ValidatedWakeConsent) throws {
    guard state == .awaitingConsent else { throw WakeCollectionError.invalidState }
    consent = validatedConsent
    state = .ready
  }

  public mutating func beginNextTake() throws -> WakeCollectionDirective {
    guard state == .ready, consent != nil, nextIndex < plan.count else {
      throw WakeCollectionError.invalidState
    }
    state = .recording
    return .startTemporaryRecording(takeID: plan[nextIndex].takeID)
  }

  public mutating func finishTake(_ evidence: WakeRecordedTakeEvidence) throws {
    guard state == .recording else { throw WakeCollectionError.invalidState }
    guard evidence.takeID == plan[nextIndex].takeID else { throw WakeCollectionError.takeMismatch }
    let maximumDuration = plan[nextIndex].label == .wake ? 5_000 : 60_000
    guard
      evidence.sampleRate == 16_000,
      evidence.channelCount == 1,
      (250...maximumDuration).contains(evidence.durationMilliseconds),
      Self.isSHA256(evidence.sha256)
    else {
      throw WakeCollectionError.invalidRecordingEvidence
    }
    pendingEvidence = evidence
    state = .reviewing
  }

  public mutating func stopAndDiscardTake() throws -> WakeCollectionDirective {
    guard state == .recording else { throw WakeCollectionError.invalidState }
    state = .ready
    return .discardTemporaryRecording(takeID: plan[nextIndex].takeID)
  }

  public mutating func acceptTake() throws -> WakeCollectionDirective {
    guard state == .reviewing, let evidence = pendingEvidence else {
      throw WakeCollectionError.invalidState
    }
    pendingEvidence = nil
    nextIndex += 1
    state = nextIndex == plan.count ? .completed : .ready
    return .retainAcceptedRecording(takeID: evidence.takeID)
  }

  public mutating func discardTake() throws -> WakeCollectionDirective {
    guard state == .reviewing, let evidence = pendingEvidence else {
      throw WakeCollectionError.invalidState
    }
    pendingEvidence = nil
    state = .ready
    return .discardTemporaryRecording(takeID: evidence.takeID)
  }

  public func publicStatus() -> WakeCollectionStatus {
    WakeCollectionStatus(
      schemaVersion: 1,
      state: state,
      completedTakeCount: nextIndex,
      totalTakeCount: plan.count
    )
  }

  private static func valid(_ take: WakeCollectionTake) -> Bool {
    !take.takeID.isEmpty
      && !take.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !take.pronunciationTag.isEmpty
      && !take.environmentTag.isEmpty
      && (20...500).contains(take.distanceCentimeters)
  }

  private static func isSHA256(_ value: String) -> Bool {
    let hexadecimal = Set("0123456789abcdef")
    return value.count == 64 && value.allSatisfy(hexadecimal.contains)
  }
}
