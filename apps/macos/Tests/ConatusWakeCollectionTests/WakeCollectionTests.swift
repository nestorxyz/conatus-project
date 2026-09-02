// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing

@testable import ConatusWakeCollection

@Suite("Consented wake collection boundary")
struct WakeCollectionTests {
  @Test("accepts only the complete explicit consent receipt")
  func validatesConsent() throws {
    _ = try WakeConsentValidator.decodeAndValidate(consentData())
  }

  @Test("rejects unknown consent fields")
  func rejectsUnknownConsentField() throws {
    var object = try #require(JSONSerialization.jsonObject(with: consentData()) as? [String: Any])
    object["email"] = "must-not-enter-the-receipt"
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: WakeCollectionError.unknownField) {
      try WakeConsentValidator.decodeAndValidate(data)
    }
  }

  @Test("rejects incomplete, duplicated, or unsafe consent")
  func rejectsInvalidConsent() throws {
    var object = try #require(JSONSerialization.jsonObject(with: consentData()) as? [String: Any])
    object["adultConfirmed"] = false
    #expect(throws: WakeCollectionError.invalidConsent) {
      try WakeConsentValidator.decodeAndValidate(try JSONSerialization.data(withJSONObject: object))
    }

    object = try #require(JSONSerialization.jsonObject(with: consentData()) as? [String: Any])
    object["permittedUses"] = ["train_wake_model", "train_wake_model"]
    #expect(throws: WakeCollectionError.invalidConsent) {
      try WakeConsentValidator.decodeAndValidate(try JSONSerialization.data(withJSONObject: object))
    }

    object = try #require(JSONSerialization.jsonObject(with: consentData()) as? [String: Any])
    object["rawAudioPublicationAllowed"] = true
    #expect(throws: WakeCollectionError.invalidConsent) {
      try WakeConsentValidator.decodeAndValidate(try JSONSerialization.data(withJSONObject: object))
    }

    object = try #require(JSONSerialization.jsonObject(with: consentData()) as? [String: Any])
    object["modelReleaseCutoffAt"] = "2026-08-01T15:00:00Z"
    #expect(throws: WakeCollectionError.invalidConsent) {
      try WakeConsentValidator.decodeAndValidate(try JSONSerialization.data(withJSONObject: object))
    }
  }

  @Test("cannot begin recording before validated consent")
  func requiresConsentBeforeRecording() throws {
    var session = try WakeCollectionSession(plan: plan())
    #expect(throws: WakeCollectionError.invalidState) {
      try session.beginNextTake()
    }
    #expect(session.publicStatus().state == .awaitingConsent)
  }

  @Test("retakes are discarded before the same planned take repeats")
  func discardsRetake() throws {
    var session = try consentedSession()
    #expect(try session.beginNextTake() == .startTemporaryRecording(takeID: "wake-001"))
    try session.finishTake(evidence(takeID: "wake-001"))
    #expect(try session.discardTake() == .discardTemporaryRecording(takeID: "wake-001"))
    #expect(try session.beginNextTake() == .startTemporaryRecording(takeID: "wake-001"))
  }

  @Test("an active take can stop and delete immediately")
  func stopsActiveTake() throws {
    var session = try consentedSession()
    _ = try session.beginNextTake()
    #expect(try session.stopAndDiscardTake() == .discardTemporaryRecording(takeID: "wake-001"))
    #expect(session.publicStatus().state == .ready)
    #expect(try session.beginNextTake() == .startTemporaryRecording(takeID: "wake-001"))
  }

  @Test("accepted takes advance in order and expose only counts")
  func completesPlan() throws {
    var session = try consentedSession()
    _ = try session.beginNextTake()
    try session.finishTake(evidence(takeID: "wake-001"))
    #expect(try session.acceptTake() == .retainAcceptedRecording(takeID: "wake-001"))
    #expect(
      session.publicStatus()
        == WakeCollectionStatus(
          schemaVersion: 1,
          state: .ready,
          completedTakeCount: 1,
          totalTakeCount: 2
        ))

    _ = try session.beginNextTake()
    try session.finishTake(evidence(takeID: "background-001", duration: 1_000))
    _ = try session.acceptTake()
    #expect(session.publicStatus().state == .completed)
    #expect(session.publicStatus().completedTakeCount == 2)
  }

  @Test("rejects mismatched or malformed recording evidence")
  func rejectsInvalidRecording() throws {
    var session = try consentedSession()
    _ = try session.beginNextTake()
    #expect(throws: WakeCollectionError.takeMismatch) {
      try session.finishTake(evidence(takeID: "background-001"))
    }
    #expect(throws: WakeCollectionError.invalidRecordingEvidence) {
      try session.finishTake(
        WakeRecordedTakeEvidence(
          takeID: "wake-001",
          sha256: String(repeating: "A", count: 64),
          sampleRate: 44_100,
          channelCount: 2,
          durationMilliseconds: 100
        ))
    }
  }

  @Test("rejects duplicate or out-of-range collection plans")
  func rejectsInvalidPlan() {
    let duplicate = [plan()[0], plan()[0]]
    #expect(throws: WakeCollectionError.invalidPlan) {
      try WakeCollectionSession(plan: duplicate)
    }
  }

  private func consentedSession() throws -> WakeCollectionSession {
    var session = try WakeCollectionSession(plan: plan())
    try session.applyConsent(WakeConsentValidator.decodeAndValidate(consentData()))
    return session
  }

  private func consentData() -> Data {
    Data(
      #"{"schemaVersion":1,"consentVersion":"conatus-wake-consent-v1","participantID":"participant_001","controllerReference":"controller_ref_001","consentedAt":"2026-09-02T15:00:00Z","rawAudioDeletionAt":"2026-12-01T15:00:00Z","modelReleaseCutoffAt":"2026-10-01T15:00:00Z","withdrawalContactReference":"contact_route_001","permittedUses":["train_wake_model","evaluate_wake_model","distribute_derived_model"],"adultConfirmed":true,"noThirdPartyVoicesConfirmed":true,"rawAudioPublicationAllowed":false,"operatorApprovalReference":"approval_ref_001"}"#
        .utf8)
  }

  private func plan() -> [WakeCollectionTake] {
    [
      WakeCollectionTake(
        takeID: "wake-001",
        label: .wake,
        prompt: "Hey Conatus",
        pronunciationTag: "es-PE",
        environmentTag: "quiet-room",
        distanceCentimeters: 50
      ),
      WakeCollectionTake(
        takeID: "background-001",
        label: .background,
        prompt: "Remain silent",
        pronunciationTag: "not-applicable",
        environmentTag: "quiet-room",
        distanceCentimeters: 50
      ),
    ]
  }

  private func evidence(takeID: String, duration: Int = 1_200) -> WakeRecordedTakeEvidence {
    WakeRecordedTakeEvidence(
      takeID: takeID,
      sha256: String(repeating: "a", count: 64),
      sampleRate: 16_000,
      channelCount: 1,
      durationMilliseconds: duration
    )
  }
}
