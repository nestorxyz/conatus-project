# Mac Runtime Boundary

Reserved for the unprivileged Machine Bridge, Codex Gateway, authenticated local
IPC, and bounded local journal. F01 intentionally includes no executor or live
Codex adapter.

## Dependency boundary

May consume generated contracts and local Codex provider schemas. It must never
expose raw shell, filesystem, MCP, App Server, or provider credentials remotely.
It cannot make Core authorization decisions or treat model output as authority.
