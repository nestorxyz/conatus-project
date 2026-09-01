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
  if (environment.NODE_ENV === "production" && isEnabled(environment.CONATUS_DEV_AUTH_BYPASS)) {
    throw new RuntimeConfigurationError();
  }
}

function isEnabled(value: string | undefined): boolean {
  return value !== undefined && ["1", "true", "yes", "on"].includes(value.toLowerCase());
}
