.PHONY: verify spike ios-spike android-spike android-native-core cryptographic-boundary-spike
verify:
	@test -f README.md
	@test -f OWNERS

spike: ios-spike android-spike cryptographic-boundary-spike

ios-spike:
	@cd ../.. && ./scripts/check-ios-terminal-spike.sh

android-spike: android-native-core
	@cd ../.. && ./scripts/check-android-terminal-spike.sh

android-native-core:
	@cd spikes/android-terminal-renderer/native-core && cargo test --locked
	@cd spikes/android-terminal-renderer/native-core && cargo clippy --locked --all-targets -- -D warnings
	@cd spikes/android-terminal-renderer/native-core && cargo fmt --check

cryptographic-boundary-spike:
	@cd spikes/cryptographic-boundaries/native-core && cargo test --locked
	@cd spikes/cryptographic-boundaries/native-core && cargo clippy --locked --all-targets -- -D warnings
	@cd spikes/cryptographic-boundaries/native-core && cargo fmt --check
