.PHONY: verify
verify:
	@test -f README.md
	@test -f OWNERS
	@test -f cddl/crypto-v1.cddl
	@grep -q '^signed-object = {' cddl/crypto-v1.cddl
	@grep -q '^epoch-manifest-proposal = {' cddl/crypto-v1.cddl
	@grep -q '^pty-frame = {' cddl/crypto-v1.cddl
