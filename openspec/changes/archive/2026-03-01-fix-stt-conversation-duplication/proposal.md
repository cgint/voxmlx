# Prevent duplicated user turns caused by STT transcript concatenation

## Why

### Summary
Speech-to-text (STT) transcript updates are currently being concatenated onto the active user message instead of treated as the latest authoritative transcript state. As a result, each subsequent partial/final update re-includes prior text, which pollutes the conversation history with duplicated phrases and entire repeated prefixes. This degrades response quality (the assistant sees repeated context), increases token usage/cost, and creates a confusing UX.

### Original user request (verbatim)
We are currently facing an issue that the text returned from the speech-to-text is always concatenated to the previous message, and therefore the conversation includes lots of duplicates. 


SeeConversation
user: Hello, sir. Hello, sir.
assistant: Hello, can you please repeat that?
user: Hello, sir. Hello, sir. Can you please tell me what...
assistant: Hello, I see you've said that twice. You can ask me anything else regarding the query.
user: Hello, sir. Hello, sir. Can you please tell me what... I want to know what is the capital of France.
assistant: The capital of France is Paris.

## What Changes

- Change transcript update handling so that partial/final STT events update the active user turn deterministically (replace/normalize), rather than blindly appending.
- Ensure that once a user turn is committed to conversation history, subsequent STT updates do not cause prior committed text to reappear in the next active turn.
- Add guardrails/tests to prevent regressions where repeated partial/final updates produce duplicated prefixes in the active turn and/or in committed user messages.

## Capabilities

### New Capabilities
- *(none)*

### Modified Capabilities
- `voice-conversation-history`: refine requirements for how transcript events update the active user turn buffer so that the active turn reflects the latest transcript for the current turn (no concatenated duplicates), even when the underlying STT session continues across multiple `final` events.

## Impact

- STT transcript event processing (partial/final) and the active user turn buffer update logic.
- Turn commit/reset logic used by manual submit and auto-submit.
- AI prompt construction quality and token usage (less duplicated context).
- Test suite: add/update unit/integration tests around transcript merging/deduplication and turn commit boundaries.
