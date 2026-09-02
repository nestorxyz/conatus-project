// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

export const REALTIME_TRANSCRIPTION_CONTRACT = Object.freeze({
  endpointPath: "/v1/realtime/transcription_sessions",
  model: "gpt-live-transcribe",
  sampleRateHz: 24_000,
  channelCount: 1,
  sampleFormat: "pcm16",
  delay: "low",
});

const maximumTurnBytes = REALTIME_TRANSCRIPTION_CONTRACT.sampleRateHz * 2 * 300;
const maximumChunkBytes = REALTIME_TRANSCRIPTION_CONTRACT.sampleRateHz * 2;
const maximumTextLength = 16_384;

export type TranscriptionFailureCode =
  | "empty_transcript"
  | "invalid_audio"
  | "invalid_state"
  | "malformed_provider_event"
  | "provider_disconnected"
  | "provider_unavailable";

export type TranscriptionEvent =
  | {
      kind: "partial";
      voiceTurnId: string;
      revision: number;
      text: string;
    }
  | {
      kind: "final";
      voiceTurnId: string;
      revision: number;
      text: string;
    }
  | {
      kind: "failed";
      voiceTurnId: string;
      revision: number;
      code: TranscriptionFailureCode;
      recoverable: boolean;
    };

export interface RealtimeTranscriptionConnection {
  send(message: Readonly<Record<string, unknown>>): Promise<void>;
  close(): Promise<void>;
}

export interface RealtimeTranscriptionTransport {
  connect(handlers: {
    onEvent: (event: unknown) => void;
    onDisconnect: () => void;
  }): Promise<RealtimeTranscriptionConnection>;
}

export class TranscriptionAdapterError extends Error {
  constructor(readonly code: TranscriptionFailureCode) {
    super(`Realtime transcription adapter failed: ${code}`);
    this.name = "TranscriptionAdapterError";
  }
}

interface TurnState {
  voiceTurnId: string;
  phase: "capturing" | "awaiting_item" | "transcribing" | "final" | "failed";
  nextAudioSequence: number;
  audioBytes: number;
  revision: number;
}

interface ProviderEventBase {
  type: string;
  eventId?: string;
}

interface ProviderItemEvent extends ProviderEventBase {
  itemId: string;
}

interface ProviderDeltaEvent extends ProviderItemEvent {
  delta: string;
}

interface ProviderCompletedEvent extends ProviderItemEvent {
  transcript: string;
}

export class RealtimeTranscriptionAdapter {
  private connection?: RealtimeTranscriptionConnection;
  private lifecycle: "idle" | "opening" | "open" | "closed" | "failed" = "idle";
  private currentTurn?: TurnState;
  private readonly pendingCommits: TurnState[] = [];
  private readonly providerItems = new Map<string, TurnState>();
  private readonly turns = new Map<string, TurnState>();
  private readonly seenProviderEventIds = new Set<string>();

  constructor(
    private readonly transport: RealtimeTranscriptionTransport,
    private readonly emit: (event: TranscriptionEvent) => void,
  ) {}

  async start(): Promise<void> {
    if (this.lifecycle !== "idle") throw new TranscriptionAdapterError("invalid_state");
    this.lifecycle = "opening";
    try {
      this.connection = await this.transport.connect({
        onEvent: (event) => this.handleProviderEvent(event),
        onDisconnect: () => this.handleDisconnect(),
      });
      if (this.isFailed()) throw new TranscriptionAdapterError("provider_unavailable");
      await this.connection.send(sessionUpdateMessage());
      if (this.isFailed()) throw new TranscriptionAdapterError("provider_unavailable");
      this.lifecycle = "open";
    } catch {
      this.lifecycle = "failed";
      try {
        await this.connection?.close();
      } catch {
        // The provider boundary is already failed; preserve the typed startup error.
      }
      throw new TranscriptionAdapterError("provider_unavailable");
    }
  }

  beginTurn(voiceTurnId: string): void {
    this.requireOpen();
    if (!validVoiceTurnId(voiceTurnId) || this.turns.has(voiceTurnId)) {
      throw new TranscriptionAdapterError("invalid_state");
    }
    if (this.currentTurn || this.pendingCommits.length > 0) {
      throw new TranscriptionAdapterError("invalid_state");
    }
    const turn: TurnState = {
      voiceTurnId,
      phase: "capturing",
      nextAudioSequence: 0,
      audioBytes: 0,
      revision: 0,
    };
    this.currentTurn = turn;
    this.turns.set(voiceTurnId, turn);
  }

  async appendAudio(voiceTurnId: string, sequence: number, pcm16Mono24k: Uint8Array): Promise<void> {
    this.requireOpen();
    const turn = this.currentTurn;
    if (!turn || turn.voiceTurnId !== voiceTurnId || turn.phase !== "capturing") {
      throw new TranscriptionAdapterError("invalid_state");
    }
    if (
      !Number.isSafeInteger(sequence)
      || sequence !== turn.nextAudioSequence
      || pcm16Mono24k.byteLength < 2
      || pcm16Mono24k.byteLength % 2 !== 0
      || pcm16Mono24k.byteLength > maximumChunkBytes
      || turn.audioBytes + pcm16Mono24k.byteLength > maximumTurnBytes
    ) {
      throw new TranscriptionAdapterError("invalid_audio");
    }
    try {
      await this.connection!.send({
        type: "input_audio_buffer.append",
        audio: Buffer.from(pcm16Mono24k).toString("base64"),
      });
    } catch {
      this.failSession("provider_unavailable", true);
      throw new TranscriptionAdapterError("provider_unavailable");
    }
    turn.nextAudioSequence += 1;
    turn.audioBytes += pcm16Mono24k.byteLength;
  }

  async commitTurn(voiceTurnId: string): Promise<void> {
    this.requireOpen();
    const turn = this.currentTurn;
    if (!turn || turn.voiceTurnId !== voiceTurnId || turn.phase !== "capturing" || turn.audioBytes === 0) {
      throw new TranscriptionAdapterError("invalid_state");
    }
    try {
      await this.connection!.send({ type: "input_audio_buffer.commit" });
    } catch {
      this.failSession("provider_unavailable", true);
      throw new TranscriptionAdapterError("provider_unavailable");
    }
    turn.phase = "awaiting_item";
    this.pendingCommits.push(turn);
    this.currentTurn = undefined;
  }

  async close(): Promise<void> {
    if (this.lifecycle === "closed") return;
    const wasOpen = this.lifecycle === "open";
    this.lifecycle = "closed";
    if (wasOpen) this.failUnfinished("provider_disconnected", true);
    await this.connection?.close();
  }

  private handleProviderEvent(value: unknown): void {
    if (this.lifecycle !== "open") return;
    const base = providerEventBase(value);
    if (!base) {
      this.failSession("malformed_provider_event", false);
      return;
    }
    if (base.eventId && this.seenProviderEventIds.has(base.eventId)) return;
    if (base.eventId) this.seenProviderEventIds.add(base.eventId);

    switch (base.type) {
      case "input_audio_buffer.committed": {
        const event = providerItemEvent(value, base);
        const turn = this.pendingCommits.shift();
        if (!event || !turn || this.providerItems.has(event.itemId)) {
          this.failSession("malformed_provider_event", false);
          return;
        }
        turn.phase = "transcribing";
        this.providerItems.set(event.itemId, turn);
        return;
      }
      case "conversation.item.input_audio_transcription.delta": {
        const event = providerDeltaEvent(value, base);
        if (!event) {
          this.failSession("malformed_provider_event", false);
          return;
        }
        const turn = this.providerItems.get(event.itemId);
        if (!turn) {
          this.failSession("malformed_provider_event", false);
          return;
        }
        if (turn.phase !== "transcribing") return;
        if (event.delta.length === 0) return;
        turn.revision += 1;
        this.emit({
          kind: "partial",
          voiceTurnId: turn.voiceTurnId,
          revision: turn.revision,
          text: event.delta,
        });
        return;
      }
      case "conversation.item.input_audio_transcription.completed": {
        const event = providerCompletedEvent(value, base);
        if (!event) {
          this.failSession("malformed_provider_event", false);
          return;
        }
        const turn = this.providerItems.get(event.itemId);
        if (!turn) {
          this.failSession("malformed_provider_event", false);
          return;
        }
        if (turn.phase !== "transcribing") return;
        const transcript = event.transcript.trim();
        if (!transcript) {
          this.failTurn(turn, "empty_transcript", true);
          return;
        }
        turn.phase = "final";
        turn.revision += 1;
        this.emit({
          kind: "final",
          voiceTurnId: turn.voiceTurnId,
          revision: turn.revision,
          text: transcript,
        });
        return;
      }
      case "error":
        this.failSession("provider_unavailable", true);
        return;
      default:
        return;
    }
  }

  private handleDisconnect(): void {
    if (this.lifecycle !== "open" && this.lifecycle !== "opening") return;
    this.lifecycle = "failed";
    this.failUnfinished("provider_disconnected", true);
  }

  private failSession(code: TranscriptionFailureCode, recoverable: boolean): void {
    this.lifecycle = "failed";
    this.failUnfinished(code, recoverable);
  }

  private failUnfinished(code: TranscriptionFailureCode, recoverable: boolean): void {
    for (const turn of this.turns.values()) {
      if (turn.phase !== "final" && turn.phase !== "failed") this.failTurn(turn, code, recoverable);
    }
  }

  private failTurn(turn: TurnState, code: TranscriptionFailureCode, recoverable: boolean): void {
    if (turn.phase === "final" || turn.phase === "failed") return;
    turn.phase = "failed";
    turn.revision += 1;
    this.emit({
      kind: "failed",
      voiceTurnId: turn.voiceTurnId,
      revision: turn.revision,
      code,
      recoverable,
    });
  }

  private requireOpen(): void {
    if (this.lifecycle !== "open") throw new TranscriptionAdapterError("invalid_state");
  }

  private isFailed(): boolean {
    return this.lifecycle === "failed";
  }
}

function sessionUpdateMessage(): Readonly<Record<string, unknown>> {
  return {
    type: "session.update",
    session: {
      type: "transcription",
      audio: {
        input: {
          format: { type: "audio/pcm", rate: REALTIME_TRANSCRIPTION_CONTRACT.sampleRateHz },
          transcription: {
            model: REALTIME_TRANSCRIPTION_CONTRACT.model,
            delay: REALTIME_TRANSCRIPTION_CONTRACT.delay,
          },
          turn_detection: null,
        },
      },
    },
  };
}

function providerEventBase(value: unknown): ProviderEventBase | undefined {
  if (!isRecord(value) || typeof value.type !== "string") return undefined;
  if (value.event_id !== undefined && !boundedString(value.event_id, 256)) return undefined;
  return { type: value.type, eventId: value.event_id as string | undefined };
}

function providerItemEvent(value: unknown, base: ProviderEventBase): ProviderItemEvent | undefined {
  if (!isRecord(value) || !boundedString(value.item_id, 256)) return undefined;
  return { ...base, itemId: value.item_id };
}

function providerDeltaEvent(value: unknown, base: ProviderEventBase): ProviderDeltaEvent | undefined {
  if (!isRecord(value)) return undefined;
  const item = providerItemEvent(value, base);
  if (!item || typeof value.delta !== "string" || value.delta.length > maximumTextLength) return undefined;
  return { ...item, delta: value.delta };
}

function providerCompletedEvent(value: unknown, base: ProviderEventBase): ProviderCompletedEvent | undefined {
  if (!isRecord(value)) return undefined;
  const item = providerItemEvent(value, base);
  if (!item || typeof value.transcript !== "string" || value.transcript.length > maximumTextLength) {
    return undefined;
  }
  return { ...item, transcript: value.transcript };
}

function validVoiceTurnId(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value);
}

function boundedString(value: unknown, maximumLength: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maximumLength;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
