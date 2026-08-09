# Alpha Execution and Approval Policy

**Status:** Approved default  
**Principle:** Deterministic machine policy is authoritative

## Outcomes

- `allow`: execute without an interactive approval.
- `prompt`: create a single-use approval bound to the canonical operation.
- `deny`: do not offer an override in alpha.

Unknown operations resolve to `deny` unless an explicit policy rule classifies them as `prompt`.

## Default policy

| Capability | Examples | Outcome |
|---|---|---|
| Registered bounded observation | Git status, bounded directory listing, process status | Allow |
| File read inside workspace | Read regular non-secret file | Allow after workspace grant |
| Sensitive file read | `.env`, credentials, key material, provider auth | Deny |
| Structured process | Tests, builds, formatter | Prompt |
| Shell string | Pipes, redirection, expansion, compound command | Prompt, elevated warning |
| File create or modify | Agent edit, formatter write | Prompt |
| File delete | Remove resolved workspace files | Prompt, destructive confirmation |
| Git observation | Status, diff, log | Allow |
| Git mutation | Add, commit, branch changes | Prompt |
| Git remote mutation | Push, force push, delete remote branch | Prompt, destructive warning where applicable |
| Dependency change | Install, update, lockfile mutation | Prompt |
| Network operation | Curl, package download, remote API | Prompt |
| Docker/container mutation | Build, start, stop, prune | Prompt; prune is destructive |
| Process termination | Stop a child owned by the run | Allow for cancellation; otherwise prompt |
| Privilege/security change | `sudo`, firewall, SSH, users, kernel settings | Deny |
| Access outside granted workspace | Arbitrary filesystem traversal | Deny in structured mode |
| Unknown plugin or tool | Unclassified MCP or agent tool | Deny |

## Canonicalization requirements

Before prompting, the Linux agent resolves the executable, ordered arguments, working directory, environment names and value hashes, resource paths, symlink policy, network targets where declared, machine, workspace, actor, policy version, expiry, and nonce. The approval UI displays the same canonical representation used for the digest.

If resolution changes before execution, the approval is invalid. Shell commands explicitly disclose that some targets are dynamic and receive an elevated warning.

## Agent relationship

Provider permissions are defense in depth. Conatus policy remains authoritative. A provider's “approved,” “safe,” or “read-only” label cannot convert `prompt` or `deny` into `allow`.

The alpha Codex adapter must use supported sandbox and approval settings and must not use flags that bypass either control.

## Policy tests

- Golden canonicalization vectors shared between approval UI and Linux agent
- Symlink and rename races
- Argument ordering and Unicode normalization
- Environment value changes
- Expiry and replay
- Concurrent approval decisions
- Membership and device revocation before consumption
- Unknown operation and unknown policy version
- Shell quoting, substitution, redirection, and alias ambiguity

