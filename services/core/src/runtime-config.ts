// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

export class RuntimeConfigurationError extends Error {
  readonly code = "development_auth_forbidden";

  constructor() {
    super("Development authentication is forbidden in production mode");
    this.name = "RuntimeConfigurationError";
  }
}

export function assertSafeRuntimeConfiguration(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): void {
  const developmentIdentityConfigured = [
    environment.CONATUS_DEV_LOCAL_TOKEN,
    environment.CONATUS_DEV_ACCOUNT_ID,
    environment.CONATUS_DEV_PRINCIPAL_ID,
  ].some((value) => value !== undefined);
  if (environment.NODE_ENV === "production"
      && (isEnabled(environment.CONATUS_DEV_AUTH_BYPASS) || developmentIdentityConfigured)) {
    throw new RuntimeConfigurationError();
  }
}

function isEnabled(value: string | undefined): boolean {
  return value !== undefined && ["1", "true", "yes", "on"].includes(value.toLowerCase());
}
