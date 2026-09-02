# Conatus Documentation

The current launch direction is [ADR 0009](decisions/0009-mac-v1-foundation.md):
Mac-first, voice-first, Codex-owned execution, TypeScript Core, and managed
activated speech. Older mobile/Linux documents remain historical and future
design evidence where ADR 0009 supersedes them.

The latest implementation evidence is recorded in [Implementation Results](../RESULT.md).

Start here:

1. [Product specification](product-spec.md)
2. [Alpha scope and acceptance](alpha-scope.md)
3. [Technical specification](technical-spec.md)
4. [Security threat model](threat-model.md)
5. [Current Mac V1 foundation](decisions/0009-mac-v1-foundation.md)
6. [Durable domain kernel](decisions/0010-durable-domain-kernel.md)
7. [Local supervision and CI](decisions/0011-local-supervision-and-ci.md)
8. [Codex App Server compatibility](decisions/0012-codex-app-server-compatibility.md)
9. [Named portfolio projection](decisions/0013-named-portfolio-projection.md)
10. [Execution and approval policy](approval-policy.md)
11. [Protocol baseline](protocol/README.md)
12. [CLI agent adapter evaluation](agent-adapter-evaluation.md)
13. [Alpha UX flows](ux-flows.md)
14. [Sequential implementation backlog](implementation-backlog.md)
15. [Licensing and contribution policy](licensing-policy.md)
16. [CI and supply-chain baseline](ci-supply-chain.md)
17. [Identity-provider decision](decisions/0007-identity-provider.md)
18. [Proposed cryptographic architecture](decisions/0008-cryptographic-architecture.md)
19. [Cryptographic design-review packet](cryptographic-design-review.md)
20. [AI-assisted cryptographic pre-review](cryptographic-design-pre-review.md)
21. [C-007 cryptographic remediation plan](cryptographic-remediation-plan.md)
22. [Pairing and recovery ceremonies](protocol/pairing-and-recovery.md)
23. [Sender-authenticated content and PTY channels](protocol/sender-authenticated-content.md)
24. [Nonce, crash, restore, and retry state](protocol/nonce-and-retry-state.md)
25. [Cryptographic byte profile v1](protocol/cryptographic-byte-profile.md)
26. [C-007-R6 platform-boundary prototype](../apps/mobile/spikes/cryptographic-boundaries/README.md)

The product, technical, and security specifications define invariants. ADRs explain durable choices. The alpha scope defines the first release boundary. The backlog orders implementation but does not override an invariant or ADR.

## Change discipline

- Change a product behavior in the product specification first.
- Change a trust boundary or security invariant in the threat model first.
- Change an accepted architectural decision through a superseding ADR.
- Change protocol semantics with compatibility analysis and golden vectors.
- Add or reorder a ticket only after updating the document that explains why.
