// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { buildApp, LocalBearerIdentityResolver, type AppOptions } from "./app.js";
import { DomainStore } from "./persistence/domain-store.js";
import { VoiceGrantStore } from "./persistence/voice-grant-store.js";
import { DurableNamedTaskCommandAuthority } from "./named-task-command-authority.js";
import { assertSafeRuntimeConfiguration, RuntimeConfigurationError } from "./runtime-config.js";

const host = process.env.CONATUS_HOST ?? "127.0.0.1";
const port = Number(process.env.CONATUS_PORT ?? "4310");
const commandCenterValues = [
  process.env.CONATUS_DATABASE_URL,
  process.env.CONATUS_DEV_LOCAL_TOKEN,
  process.env.CONATUS_DEV_ACCOUNT_ID,
  process.env.CONATUS_DEV_PRINCIPAL_ID,
];
const configuredCount = commandCenterValues.filter(Boolean).length;
if (configuredCount !== 0 && configuredCount !== commandCenterValues.length) {
  throw new Error("Local command center requires database, token, account, and principal configuration");
}
const store = configuredCount === commandCenterValues.length
  ? new DomainStore(process.env.CONATUS_DATABASE_URL!)
  : undefined;
const voiceGrantStore = store ? new VoiceGrantStore(process.env.CONATUS_DATABASE_URL!) : undefined;
const identityResolver = store
  ? new LocalBearerIdentityResolver(process.env.CONATUS_DEV_LOCAL_TOKEN!, {
      accountId: process.env.CONATUS_DEV_ACCOUNT_ID!,
      principalId: process.env.CONATUS_DEV_PRINCIPAL_ID!,
    })
  : undefined;
const options: AppOptions = store ? {
  commandCenter: {
    identityResolver: identityResolver!,
    portfolioReader: store,
  },
  voiceGrants: {
    identityResolver: identityResolver!,
    authority: voiceGrantStore!,
  },
  namedTaskCommands: {
    identityResolver: identityResolver!,
    authority: new DurableNamedTaskCommandAuthority(store),
  },
} : {};
const app = buildApp(options);
if (store && voiceGrantStore) {
  app.addHook("onClose", async () => {
    await Promise.all([store.close(), voiceGrantStore.close()]);
  });
}

try {
  assertSafeRuntimeConfiguration();
  await app.listen({ host, port });
} catch (error) {
  if (error instanceof RuntimeConfigurationError) {
    console.error(`startup_error:${error.code}`);
  } else {
    app.log.error(error);
  }
  process.exitCode = 1;
}
