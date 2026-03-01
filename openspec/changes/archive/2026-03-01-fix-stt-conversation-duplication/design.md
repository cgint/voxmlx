# Stop STT transcript updates from duplicating previously spoken text

## Context

The `stt_playground/` Phoenix LiveView app maintains an in-memory conversation history and an “active user turn” buffer that is updated by STT transcript events (partial/final). Today, the active turn text ends up accumulating duplicated prefixes (and sometimes whole prior turns), which then gets committed into conversation history and fed back into the AI prompt.

This is especially likely when the STT session is kept open across multiple `final` events (see existing `stt-session-continuity` capability). In that mode, some STT providers/workers emit transcript strings that are *cumulative for the session* (or otherwise not clean deltas), so naïvely appending incoming transcript text to the active turn will repeatedly re-add already-seen content.

Constraints:
- Keep existing UX/flow: recording stays on; STT session continuity remains.
- Keep existing conversation model: committed history is discrete messages; active turn is separate (per `voice-conversation-history`).
- Fix should be resilient to partial/final “rewrite” behavior where the model corrects earlier words.

## Goals / Non-Goals

**Goals:**
- Ensure the active user turn reflects the latest transcript for the current turn (authoritative update), not a concatenation of prior updates.
- Ensure a newly committed user message is not repeated as a prefix of the next user message.
- Keep behavior consistent for both manual submit and auto-submit.
- Add test coverage that fails under the current buggy behavior and passes with the new logic.

**Non-Goals:**
- Changing the STT model/worker output format (unless required as a follow-up change).
- Perfect linguistic diffing across arbitrary punctuation/normalization differences; we will aim for pragmatic, robust behavior.
- Persisting conversation history beyond in-memory scope.

## Decisions

### Decision 1: Treat each STT event’s transcript as a snapshot, not an append-only delta
**Choice:** The LiveView state update for the active turn will be based on *replacement* of the active turn text derived from the latest transcript snapshot.

**Rationale:** Partial/final transcripts often revise prior text. Append-based handling is inherently unsafe and is the direct cause of duplicated prefixes.

**Alternative considered:** Append-only + heuristics to detect repetition. Rejected because it fails when STT rewrites earlier words.

### Decision 2: Compute “current turn text” from a turn-start anchor when STT output is cumulative
**Choice:** Track a `turn_start_transcript_snapshot` (per active STT session) representing the most recent full/session transcript at the moment a new turn begins. For each incoming transcript snapshot `T`, derive the active turn text as `T - turn_start_transcript_snapshot` (remove prefix) after normalization.

**Rationale:** With session continuity, transcript snapshots may include earlier turns. Anchoring at turn start provides a stable way to avoid re-introducing committed history into the active turn.

**Alternative considered:** Force a new STT session per turn. Rejected because it conflicts with `stt-session-continuity` and increases churn/latency.

### Decision 3: Use conservative normalization + prefix removal, with a safe fallback
**Choice:** Apply lightweight normalization (trim, collapse whitespace) when comparing/removing prefixes. If the new snapshot is not a prefix-extension of the anchor (e.g., heavy punctuation changes), fall back to treating the entire snapshot as the active turn *and* reset the anchor so subsequent updates stabilize.

**Rationale:** Prevents the UI from showing an empty/incorrect active turn when the provider slightly changes formatting.

**Alternative considered:** Full diff algorithm (token-level / LCS). Rejected for now due to complexity; can be a follow-up if needed.

## Risks / Trade-offs

- **[Risk] Prefix removal fails due to punctuation/normalization differences** → **Mitigation:** normalize whitespace; include fallback path; add tests for common variants.
- **[Risk] Some providers emit true deltas (not cumulative) and anchor removal could remove too much** → **Mitigation:** detect when snapshot does *not* start with anchor and do not subtract; treat as per-turn snapshot.
- **[Trade-off] Fallback may temporarily show more text than desired** (worst case: full cumulative transcript in active turn) → **Mitigation:** anchor reset should converge; this is still better than permanent duplication.

## Migration Plan

- No data migration expected (state is in-memory).
- Rollout by deploying updated LiveView transcript handling + new tests.
- Rollback by reverting the transcript handling changes.

## Open Questions

- What is the exact STT event payload shape from `stt_port_worker.py` to the LiveView (do we have `session_id`, `final`/`partial`, and is `text` cumulative)?
- Do we have explicit segment identifiers/timestamps that could enable a more precise “new text since last segment” approach?
- Should the anchor be reset on manual submit/auto-submit only, or also on explicit speech-activity transitions?
