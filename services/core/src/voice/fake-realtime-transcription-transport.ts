// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import type {
  RealtimeTranscriptionConnection,
  RealtimeTranscriptionTransport,
} from "./realtime-transcription-adapter.js";

export class FakeRealtimeTranscriptionTransport implements RealtimeTranscriptionTransport {
  readonly sentMessages: Readonly<Record<string, unknown>>[] = [];
  private handlers?: {
    onEvent: (event: unknown) => void;
    onDisconnect: () => void;
  };
  private connected = false;
  private closed = false;
  failNextSend = false;

  get isClosed(): boolean {
    return this.closed;
  }

  async connect(handlers: {
    onEvent: (event: unknown) => void;
    onDisconnect: () => void;
  }): Promise<RealtimeTranscriptionConnection> {
    if (this.connected) throw new Error("Fake transport accepts one connection");
    this.connected = true;
    this.handlers = handlers;
    return {
      send: async (message) => {
        if (this.closed) throw new Error("Fake transport is closed");
        if (this.failNextSend) {
          this.failNextSend = false;
          throw new Error("Synthetic send failure");
        }
        this.sentMessages.push(structuredClone(message));
      },
      close: async () => {
        this.closed = true;
      },
    };
  }

  emit(event: unknown): void {
    if (!this.handlers || this.closed) throw new Error("Fake transport is not open");
    this.handlers.onEvent(structuredClone(event));
  }

  disconnect(): void {
    if (!this.handlers || this.closed) throw new Error("Fake transport is not open");
    this.closed = true;
    this.handlers.onDisconnect();
  }
}
