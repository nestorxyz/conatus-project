// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { NamedTaskCommandResponse } from "@conatus/contracts";
import type { CommandRecord } from "./domain/types.js";

export interface NamedTaskCommandStore {
  submitNamedTaskCommand(input: {
    accountId: string;
    principalId: string;
    voiceTurnId: string;
    workspaceId: string;
    productId: string;
    projectId: string;
    taskId: string;
    text: string;
  }): Promise<CommandRecord>;
}

export class DurableNamedTaskCommandAuthority {
  constructor(private readonly store: NamedTaskCommandStore) {}

  async admit(input: {
    accountId: string;
    principalId: string;
    voiceTurnId: string;
    workspaceId: string;
    productId: string;
    projectId: string;
    taskId: string;
    text: string;
  }): Promise<NamedTaskCommandResponse> {
    const command = await this.store.submitNamedTaskCommand(input);
    return {
      schemaVersion: 1,
      voiceTurnId: input.voiceTurnId,
      taskId: command.taskId,
      commandId: command.commandId,
      state: "accepted",
    };
  }
}
