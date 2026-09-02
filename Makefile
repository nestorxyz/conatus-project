# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

.PHONY: bootstrap verify format lint test lock-check secret-scan license-scan sbom historical-spikes f01 f03 m1-01 m1-02 m1-03 m1-04-live m1-05 ci

bootstrap verify:
	@./scripts/bootstrap.sh

format:
	@./scripts/check-format.sh

lint:
	@./scripts/lint.sh

test:
	@./scripts/test-quality-gates.sh

lock-check:
	@./scripts/check-lockfiles.sh

secret-scan:
	@./scripts/check-secrets.sh

license-scan:
	@./scripts/check-licensing.sh
	@./scripts/check-dependency-licenses.sh

sbom:
	@./scripts/generate-sbom.sh

historical-spikes:
	@$(MAKE) --no-print-directory -C apps/mobile spike
	@$(MAKE) --no-print-directory -C services/control-plane spike

f01:
	@pnpm check:f01

f03:
	@pnpm check:f03

m1-01:
	@pnpm check:m1-01

m1-02:
	@pnpm check:m1-02

m1-03:
	@pnpm check:m1-03

m1-04-live:
	@pnpm check:m1-04:live

m1-05:
	@pnpm check:m1-05

ci: bootstrap format lint test lock-check secret-scan license-scan
