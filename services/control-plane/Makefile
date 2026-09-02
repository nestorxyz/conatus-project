.PHONY: verify spike

spike:
	@cd spikes/rust-web-stack && cargo test --locked
	@cd spikes/rust-web-stack && cargo clippy --locked --all-targets -- -D warnings
	@cd spikes/rust-web-stack && cargo fmt --check

verify:
	@test -f README.md
	@test -f OWNERS
