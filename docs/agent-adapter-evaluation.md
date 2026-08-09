# CLI Agent Adapter Evaluation

**Status:** Decision made for alpha  
**Decision:** Codex is the first structured adapter; all agents remain available through PTY

## Evaluation criteria

1. Machine-readable streaming lifecycle
2. Stable session identifier and explicit resume
3. Tool, command, and file-change visibility
4. Permission or approval integration
5. Cancellation and exit semantics
6. Linux support
7. Authentication owned by the user on the machine
8. Version detection and compatibility behavior
9. Ability to preserve raw provider events
10. License and redistribution constraints

## Findings

### Codex

Official OpenAI documentation describes `codex exec` as stable non-interactive execution. `--json` emits JSONL events including thread and turn lifecycle plus agent messages, command executions, file changes, MCP calls, searches, and plan updates. `codex exec resume <SESSION_ID>` resumes a named session. Sandbox and approval settings can be preset.

This provides the best direct mapping to Conatus `RunEvent` objects for the first adapter. The alpha adapter launches the user's installed CLI and uses the user's existing local authentication. Conatus must never copy or upload the Codex authentication file.

References:

- <https://developers.openai.com/codex/noninteractive>
- <https://developers.openai.com/codex/cli/reference>

### Claude Code

Claude Code supports print mode, streaming JSON input/output, explicit session IDs and resume, tool allow/deny configuration, permission modes, and a permission-prompt tool. It is a strong candidate for the second structured adapter.

The adapter should prefer supported structured and permission interfaces rather than parsing the interactive TUI. Local user authentication remains outside Conatus custody.

Reference: <https://code.claude.com/docs/en/cli-usage>

### Gemini CLI

Gemini CLI headless mode provides streaming JSONL events for session initialization, messages, tool use, tool results, errors, and final results. Its open-source implementation and hook/policy surface make it a strong third adapter candidate. Resume and permission behavior must be verified against a pinned stable release before adapter implementation.

References:

- <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/headless.md>
- <https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/tools.md>

## Two integration levels

### Level 0: PTY compatibility

Conatus starts any installed CLI inside a user-visible terminal. It knows only process and PTY lifecycle. This is required in alpha for Codex, Claude Code, Gemini CLI, and other agents.

### Level 1: Structured adapter

Conatus invokes a documented machine-readable mode and normalizes provider events. It can render agent messages, tools, commands, file changes, usage, errors, and completion as blocks.

Conatus never claims a provider supports structured approval or resume until the pinned-version contract test proves it.

## Codex alpha contract

The adapter must:

- Discover `codex` from the user environment and report its exact version.
- Require a Git workspace unless the product later exposes an explicit reviewed exception.
- Launch non-interactive execution with JSONL output and an explicit working directory.
- Parse incrementally with line and event-size limits.
- Preserve unknown event types and encrypted raw events.
- Record the returned thread/session identifier.
- Resume only by the recorded identifier, never by ambiguous “last session” selection.
- Translate process exit, malformed JSON, incompatible schema, authentication failure, and interruption into distinct provider errors.
- Never use dangerous sandbox or approval bypass flags.
- Never read, transmit, or manage the user's provider authentication secrets.
- Pin a tested version range and fail safely outside it while still offering PTY mode.

## Spike required before production adapter

Create a disposable Linux repository and a provider contract harness. Capture golden JSONL for:

- Text-only completion
- Shell tool execution
- File modification
- Failed command
- Cancellation
- Authentication failure
- Resume by session ID
- Unknown event injection
- Output exceeding limits
- An operation that requires approval under supported settings

The spike may change adapter mechanics but must not change Conatus session, run, approval, or audit semantics.

