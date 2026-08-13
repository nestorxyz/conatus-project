.PHONY: verify
verify:
	@test -f README.md
	@test -f OWNERS
	@test -f crypto/authority-transition-cases-v1.json
	@test "$$(grep -c '"id": "R1-' crypto/authority-transition-cases-v1.json)" -eq 16
	@grep -q '"expected": "security_fork"' crypto/authority-transition-cases-v1.json
	@test -f crypto/pairing-recovery-cases-v1.json
	@test "$$(grep -c '"id": "R2-' crypto/pairing-recovery-cases-v1.json)" -eq 24
	@grep -q 'Noise_XXpsk3_25519_ChaChaPoly_SHA256' crypto/pairing-recovery-cases-v1.json
	@test -f crypto/sender-channel-cases-v1.json
	@test "$$(grep -c '"id": "R3-' crypto/sender-channel-cases-v1.json)" -eq 30
	@grep -q 'Noise_KK_25519_ChaChaPoly_SHA256' crypto/sender-channel-cases-v1.json
	@test -f crypto/nonce-retry-cases-v1.json
	@test "$$(grep -c '"id": "R4-' crypto/nonce-retry-cases-v1.json)" -eq 30
	@grep -q 'zero-repeated-key-nonce-encryption-invocations' crypto/nonce-retry-cases-v1.json
	@test -f crypto/crypto-byte-profile-v1.json
	@test "$$(grep -c '"id": "N-' crypto/crypto-byte-profile-v1.json)" -eq 45
	@test "$$(grep -c '"canonical_hex":' crypto/crypto-byte-profile-v1.json)" -eq 32
	@grep -q 'hpke_ciphertext_hex' crypto/crypto-byte-profile-v1.json
	@grep -q 'es256_signature_raw_low_s_hex' crypto/crypto-byte-profile-v1.json
	@grep -q 'RFC 9180 Appendix A.2.1' crypto/crypto-byte-profile-v1.json
