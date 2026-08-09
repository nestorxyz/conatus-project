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

The product, technical, and security specifications define invariants. ADRs explain durable choices. The alpha scope defines the first release boundary. The backlog orders implementation but does not override an invariant or ADR.

## Change discipline

- Change a product behavior in the product specification first.
- Change a trust boundary or security invariant in the threat model first.
- Change an accepted architectural decision through a superseding ADR.
- Change protocol semantics with compatibility analysis and golden vectors.
- Add or reorder a ticket only after updating the document that explains why.
