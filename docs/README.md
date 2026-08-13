# Conatus Documentation

Start here:

1. [Product specification](product-spec.md)
2. [Alpha scope and acceptance](alpha-scope.md)
3. [Technical specification](technical-spec.md)
4. [Security threat model](threat-model.md)
5. [Foundation decisions](decisions/0001-foundation.md)
6. [Execution and approval policy](approval-policy.md)
7. [Protocol baseline](protocol/README.md)
8. [CLI agent adapter evaluation](agent-adapter-evaluation.md)
9. [Alpha UX flows](ux-flows.md)
10. [Sequential implementation backlog](implementation-backlog.md)
11. [Licensing and contribution policy](licensing-policy.md)
12. [CI and supply-chain baseline](ci-supply-chain.md)
13. [Identity-provider decision](decisions/0007-identity-provider.md)
14. [Proposed cryptographic architecture](decisions/0008-cryptographic-architecture.md)
15. [Cryptographic design-review packet](cryptographic-design-review.md)
16. [AI-assisted cryptographic pre-review](cryptographic-design-pre-review.md)
17. [C-007 cryptographic remediation plan](cryptographic-remediation-plan.md)
18. [Pairing and recovery ceremonies](protocol/pairing-and-recovery.md)
19. [Sender-authenticated content and PTY channels](protocol/sender-authenticated-content.md)
20. [Nonce, crash, restore, and retry state](protocol/nonce-and-retry-state.md)
21. [Cryptographic byte profile v1](protocol/cryptographic-byte-profile.md)
22. [C-007-R6 platform-boundary prototype](../apps/mobile/spikes/cryptographic-boundaries/README.md)

The product, technical, and security specifications define invariants. ADRs explain durable choices. The alpha scope defines the first release boundary. The backlog orders implementation but does not override an invariant or ADR.

## Change discipline

- Change a product behavior in the product specification first.
- Change a trust boundary or security invariant in the threat model first.
- Change an accepted architectural decision through a superseding ADR.
- Change protocol semantics with compatibility analysis and golden vectors.
- Add or reorder a ticket only after updating the document that explains why.
