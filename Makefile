# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

.PHONY: bootstrap verify format lint test lock-check secret-scan license-scan sbom f01 f03 ci

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

f01:
	@pnpm check:f01

f03:
	@pnpm check:f03

ci: bootstrap format lint test lock-check secret-scan license-scan
