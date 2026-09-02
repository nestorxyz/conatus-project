// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { FakeRealtimeTranscriptionTransport } from "./fake-realtime-transcription-transport.js";
import {
  REALTIME_TRANSCRIPTION_CONTRACT,
  RealtimeTranscriptionAdapter,
  TranscriptionAdapterError,
  type TranscriptionEvent,
} from "./realtime-transcription-adapter.js";

function fixture() {
  const transport = new FakeRealtimeTranscriptionTransport();
  const events: TranscriptionEvent[] = [];
  const adapter = new RealtimeTranscriptionAdapter(transport, (event) => events.push(event));
  return { adapter, transport, events };
}

function audio(sampleCount = 240): Uint8Array {
  return new Uint8Array(sampleCount * 2).fill(7);
}

async function commitAndBind(
  adapter: RealtimeTranscriptionAdapter,
  transport: FakeRealtimeTranscriptionTransport,
  voiceTurnId: string,
  itemId: string,
): Promise<void> {
  adapter.beginTurn(voiceTurnId);
  await adapter.appendAudio(voiceTurnId, 0, audio());
  await adapter.commitTurn(voiceTurnId);
  transport.emit({ type: "input_audio_buffer.committed", item_id: itemId });
}

test("pins the current transcription-only provider session without credentials or automatic VAD", async () => {
  const { adapter, transport } = fixture();
  await adapter.start();
  assert.deepEqual(REALTIME_TRANSCRIPTION_CONTRACT, {
    endpointPath: "/v1/realtime/transcription_sessions",
    model: "gpt-live-transcribe",
    sampleRateHz: 24_000,
    channelCount: 1,
    sampleFormat: "pcm16",
    delay: "low",
  });
  assert.deepEqual(transport.sentMessages[0], {
    type: "session.update",
    session: {
      type: "transcription",
      audio: {
        input: {
          format: { type: "audio/pcm", rate: 24_000 },
          transcription: { model: "gpt-live-transcribe", delay: "low" },
          turn_detection: null,
        },
      },
    },
  });
  const wire = JSON.stringify(transport.sentMessages);
  for (const forbidden of ["api_key", "authorization", "credential", "bearer "]) {
    assert.equal(wire.toLowerCase().includes(forbidden), false);
  }
  await adapter.close();
});

test("closes the transport when pinned session configuration fails", async () => {
  const { adapter, transport } = fixture();
  transport.failNextSend = true;
  await assert.rejects(
    adapter.start(),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "provider_unavailable",
  );
  assert.equal(transport.isClosed, true);
});

test("sends ordered bounded PCM chunks and explicitly commits one turn", async () => {
  const { adapter, transport } = fixture();
  await adapter.start();
  adapter.beginTurn("voice-turn-1");
  await adapter.appendAudio("voice-turn-1", 0, audio(120));
  await adapter.appendAudio("voice-turn-1", 1, audio(240));
  await adapter.commitTurn("voice-turn-1");
  assert.deepEqual(transport.sentMessages.slice(1).map((message) => message.type), [
    "input_audio_buffer.append",
    "input_audio_buffer.append",
    "input_audio_buffer.commit",
  ]);
  await assert.rejects(
    adapter.appendAudio("voice-turn-1", 2, audio()),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "invalid_state",
  );
  assert.throws(
    () => adapter.beginTurn("voice-turn-2"),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "invalid_state",
  );
  await adapter.close();
});

test("reconciles partials and out-of-order finals by provider item without exposing provider ids", async () => {
  const { adapter, transport, events } = fixture();
  await adapter.start();
  await commitAndBind(adapter, transport, "voice-turn-1", "provider-item-a");
  await commitAndBind(adapter, transport, "voice-turn-2", "provider-item-b");

  transport.emit({
    type: "conversation.item.input_audio_transcription.delta",
    event_id: "provider-event-b1",
    item_id: "provider-item-b",
    delta: "Second ",
  });
  transport.emit({
    type: "conversation.item.input_audio_transcription.delta",
    event_id: "provider-event-a1",
    item_id: "provider-item-a",
    delta: "First ",
  });
  transport.emit({
    type: "conversation.item.input_audio_transcription.completed",
    event_id: "provider-event-b2",
    item_id: "provider-item-b",
    transcript: "Second command",
  });
  transport.emit({
    type: "conversation.item.input_audio_transcription.completed",
    event_id: "provider-event-a2",
    item_id: "provider-item-a",
    transcript: "First command",
  });

  assert.deepEqual(events, [
    { kind: "partial", voiceTurnId: "voice-turn-2", revision: 1, text: "Second " },
    { kind: "partial", voiceTurnId: "voice-turn-1", revision: 1, text: "First " },
    { kind: "final", voiceTurnId: "voice-turn-2", revision: 2, text: "Second command" },
    { kind: "final", voiceTurnId: "voice-turn-1", revision: 2, text: "First command" },
  ]);
  const productEvents = JSON.stringify(events);
  for (const forbidden of ["provider-item", "provider-event", "gpt-live-transcribe"]) {
    assert.equal(productEvents.includes(forbidden), false);
  }
  await adapter.close();
});

test("deduplicates provider events and emits exactly one final per voice turn", async () => {
  const { adapter, transport, events } = fixture();
  await adapter.start();
  await commitAndBind(adapter, transport, "voice-turn-1", "provider-item-a");
  const final = {
    type: "conversation.item.input_audio_transcription.completed",
    event_id: "provider-final-a",
    item_id: "provider-item-a",
    transcript: "Do the work",
  };
  transport.emit({
    type: "conversation.item.input_audio_transcription.delta",
    item_id: "provider-item-a",
    delta: "",
  });
  assert.deepEqual(events, []);
  transport.emit(final);
  transport.emit(final);
  transport.emit({
    type: "conversation.item.input_audio_transcription.delta",
    item_id: "provider-item-a",
    delta: "late",
  });
  assert.deepEqual(events, [
    { kind: "final", voiceTurnId: "voice-turn-1", revision: 1, text: "Do the work" },
  ]);
  await adapter.close();
});

test("fails closed on malformed mapped events without leaking provider payload", async () => {
  const { adapter, transport, events } = fixture();
  await adapter.start();
  await commitAndBind(adapter, transport, "voice-turn-1", "provider-item-a");
  transport.emit({
    type: "conversation.item.input_audio_transcription.completed",
    item_id: "unknown-provider-item-with-private-detail",
    transcript: "private provider transcript",
  });
  assert.deepEqual(events, [{
    kind: "failed",
    voiceTurnId: "voice-turn-1",
    revision: 1,
    code: "malformed_provider_event",
    recoverable: false,
  }]);
  assert.equal(JSON.stringify(events).includes("private"), false);
});

test("validates provider item binding before ignoring an empty delta", async () => {
  const { adapter, transport, events } = fixture();
  await adapter.start();
  await commitAndBind(adapter, transport, "voice-turn-1", "provider-item-a");
  transport.emit({
    type: "conversation.item.input_audio_transcription.delta",
    item_id: "unknown-provider-item",
    delta: "",
  });
  assert.deepEqual(events, [{
    kind: "failed",
    voiceTurnId: "voice-turn-1",
    revision: 1,
    code: "malformed_provider_event",
    recoverable: false,
  }]);
});

test("maps empty finals and disconnects to typed recoverable turn failures", async () => {
  const empty = fixture();
  await empty.adapter.start();
  await commitAndBind(empty.adapter, empty.transport, "voice-turn-empty", "provider-item-empty");
  empty.transport.emit({
    type: "conversation.item.input_audio_transcription.completed",
    item_id: "provider-item-empty",
    transcript: "   ",
  });
  assert.deepEqual(empty.events, [{
    kind: "failed",
    voiceTurnId: "voice-turn-empty",
    revision: 1,
    code: "empty_transcript",
    recoverable: true,
  }]);

  const disconnected = fixture();
  await disconnected.adapter.start();
  await commitAndBind(
    disconnected.adapter,
    disconnected.transport,
    "voice-turn-disconnected",
    "provider-item-disconnected",
  );
  disconnected.transport.disconnect();
  assert.deepEqual(disconnected.events, [{
    kind: "failed",
    voiceTurnId: "voice-turn-disconnected",
    revision: 1,
    code: "provider_disconnected",
    recoverable: true,
  }]);
});

test("rejects gapped, malformed, oversized, and failed audio sends without advancing", async () => {
  const { adapter, transport, events } = fixture();
  await adapter.start();
  adapter.beginTurn("voice-turn-audio");
  await assert.rejects(
    adapter.appendAudio("voice-turn-audio", 1, audio()),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "invalid_audio",
  );
  await assert.rejects(
    adapter.appendAudio("voice-turn-audio", 0, new Uint8Array(3)),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "invalid_audio",
  );
  transport.failNextSend = true;
  await assert.rejects(
    adapter.appendAudio("voice-turn-audio", 0, audio()),
    (error: unknown) => error instanceof TranscriptionAdapterError && error.code === "provider_unavailable",
  );
  assert.deepEqual(events, [{
    kind: "failed",
    voiceTurnId: "voice-turn-audio",
    revision: 1,
    code: "provider_unavailable",
    recoverable: true,
  }]);
});
