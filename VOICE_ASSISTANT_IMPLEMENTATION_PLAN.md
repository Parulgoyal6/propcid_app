# Flutter AI Voice Assistant — Implementation Plan

**Status: PLAN ONLY. No implementation has been done.** This document describes what would be built, based on `VOICE_ASSISTANT_ANALYSIS.md`'s findings on the website's actual implementation. Every design choice below either reuses an existing backend contract verbatim or explicitly says why it can't be identical (a genuinely web-only mechanism) and what the Flutter equivalent would be.

## Context

The website's voice assistant is a global, tap-to-talk conversational agent: speech → OpenAI-powered transcription → a JSON-intent-classifying chat completion → a client-side tool registry that navigates, searches, or writes data → optional spoken response. `VOICE_ASSISTANT_ANALYSIS.md` documents this in full, including two important facts that shape this plan:

1. **It does not use OpenAI's function-calling API.** It's prompt-engineered JSON output, parsed and dispatched client-side. This is good news for reuse — the mechanism is just "send a prompt, get JSON back," which is trivial to replicate from Dart against the *same* Edge Function.
2. **Search and navigation are pure deep-links**, not duplicated query logic. The voice tool never re-implements filtering — it just sets URL params and lets the existing search page do the work. The direct Flutter equivalent is: set `FilterProvider` state and call `PropertyProvider.runSearch()` — both already built and already fixed (see the filter/map bug-fix work earlier in this project).

**What already exists in this Flutter app that this plan builds on, not around:**
- `lib/services/ai_search_service.dart` — already calls `openai-proxy/chat/completions` via `Supabase.instance.client.functions.invoke(...)` and parses a structured JSON result. This is proof the exact reuse pattern this plan needs already works in this codebase.
- `lib/services/voice_search_service.dart` — already does voice input, but via the **on-device** `speech_to_text` package, not the website's OpenAI-audio-endpoint approach. This is a real fork in the road, discussed in "Open Decisions" below — it is a different, simpler feature (one-shot dictation into a text box) from what this plan describes (a persistent, global, multi-turn conversational agent), and the two can coexist.
- `FilterProvider`, `PropertyProvider.runSearch()`, `PropertyService`, `AvailableLocationsProvider` — the entire already-working search/filter pipeline this plan reuses rather than re-implementing.
- `app.dart`'s named-route table and `AppConstants` route-name constants — reused for navigation resolution instead of building a new routing scheme.

## Requirements → how each is satisfied

| Requirement | How |
|---|---|
| Backend unchanged | Nothing in this plan touches `propcid-main` or Supabase migrations/functions. Every call target already exists and is already deployed. |
| Reuse existing AI APIs | Same `openai-proxy` Edge Function, same three sub-paths (`/chat/completions`, `/audio/transcriptions`, `/audio/speech`), same auth pattern (`apikey` + `Authorization: Bearer <session or anon>`), same request/response shapes. |
| Reuse existing Edge Functions | `openai-proxy` (already called from `AiSearchService`) and, optionally, `ai-knowledge` for RAG grounding — no new Edge Function is written. |
| Reuse existing prompts | The website's `prompt.ts` text is ported into a Dart file as close to verbatim as possible (see "Prompt Reuse Strategy"), not rewritten from scratch. Same JSON response envelope, same intent taxonomy for the tools that are in scope. |
| Reuse existing business logic | The route-resolution rules, the search-deep-link parameter names, and the permission-tiering rules are translated line-for-line from the website's `navigationTool.ts`/`searchTools.ts`/permission logic, not reinvented. |

## Scope

**In scope** (matches `VOICE_ASSISTANT_ANALYSIS.md` §12's own recommendation for what's mobile-relevant):
- Voice activation (tap-to-talk, global floating button)
- Speech-to-text
- Multi-turn AI conversation with the same JSON-intent contract
- Navigation by voice (`navigate` tool)
- Property search by voice (`search_properties`, `compare_properties`)
- Opening screens by voice (profile, saved properties/shortlist, notifications, visit bookings — the Tier-2 tools already meaningful on mobile)
- Search filters by voice (voice-driven `FilterProvider` changes)
- Context-aware conversations (multi-turn history, carried exactly as the website carries it)

**Out of scope** (already excluded from mobile per this project's earlier scoping decisions, and independently recommended by the analysis doc):
- All admin tools (`authTool.ts`'s actual content — user banning, property/article moderation, platform settings)
- All CRM/CMS/video/dashboard tools (`crmTools.ts`, `cmsTools.ts`, `videoTools.ts`, `dashboardTools.ts`)
- Voice-driven property/listing **creation** (`create_listing`, `update_listing`, `delete_listing`, `publish_listing`) — this is back-office/seller-side content-creation work, and Post Property is itself still a separate, not-yet-functional milestone in this app; voice authoring on top of an incomplete manual flow isn't a sound sequencing choice. Flagged for a later phase once Post Property itself works.
- `logout`/`delete_account` — trivial to add later, deliberately left out of v1 given the destructive/irreversible nature of `delete_account` specifically warrants its own confirmation-flow review.

## Architecture

Mirrors the website's five layers, translated to this app's existing Provider-based conventions:

```
UI layer            VoiceAssistantButton (FAB, existing app style)
                     + VoiceAssistantSheet (modal bottom sheet — mobile-appropriate
                       equivalent of the website's slide-in side panel)
                     + ConversationHistoryList + status/waveform indicator
                                         │
Orchestration layer  VoiceAssistantProvider (ChangeNotifier — same pattern as every
                     other provider in this app), state enum (idle/listening/
                     processing/speaking/error), processText() turn pipeline
                                         │
         ┌───────────────────┬──────────┴───────────┬────────────────────┐
         ▼                   ▼                       ▼                    ▼
   VoiceIOService      AiConversationService     ToolRegistry          ConversationHistoryStore
   (STT + TTS, new)    (the "brain" — extends     (Map<String,           (shared_preferences-
                        the AiSearchService        ToolDefinition>,       backed ring buffer,
                        pattern into full           dispatched by         mirrors
                        multi-turn chat)            intent string)        conversationManager.ts)
         │                   │                       │
         ▼                   ▼                       ▼
   openai-proxy         openai-proxy            Dart tool files (navigationTool.dart,
   /audio/transcriptions /chat/completions       searchTools.dart, accountTools.dart —
   /audio/speech         (same model, same        one file per website category that's
   (existing function)   server-side control)     actually in scope)
                                                        │
                                          each tool does ONE of: navigate(route) |
                                          set FilterProvider state + PropertyProvider
                                          .runSearch() | read from an existing provider
```

## Data flow (one turn, Flutter terms)

1. User taps the floating **VoiceAssistantButton** → `VoiceAssistantProvider.startListening()` → state → `listening`.
2. `VoiceIOService` records audio (needs a recording package — see "New Dependencies"), auto-stopping on a silence-detection heuristic ported from the website's RMS-energy approach, or on a max-duration timer.
3. Recorded audio is uploaded to `openai-proxy/audio/transcriptions` (same endpoint `AiSearchService` already proves reachable) → transcript text returned.
4. `VoiceAssistantProvider.processText(transcript)` → state → `processing`.
5. Build the request exactly as the website does:
   - `history` = last N turns from `ConversationHistoryStore`, excluding the one just added.
   - `systemPrompt` = built by a ported `buildSystemPrompt()` Dart function — same tiering (guest vs. authenticated; admin tier omitted since admin tools are out of scope), using the *current* Flutter auth/profile state (`AuthProvider`, wherever role/user_type already live in this app).
   - Optional grounding context from `ai-knowledge` (can be deferred to a later phase — see "Open Decisions").
6. POST to `openai-proxy/chat/completions` (same call shape as `AiSearchService.parseQuery`, extended to carry a full message array instead of one single-shot prompt).
7. Parse the JSON response into the same `AgentResponse` shape (`intent`, `parameters`, `response`, `needs_confirmation`, `missing_fields`, `complete`); malformed JSON falls back to `intent: 'unknown'`, exactly as the website does.
8. Confirmation resolution: if the user is answering "yes" to a previously staged action, swap in the original staged intent/parameters (same `workflowState` concept as the website).
9. Dispatch gate (`shouldExecuteTool` — ported 1:1, it's pure logic with no web dependency): skip execution for `unknown`/pure-Q&A intents, or if the turn still needs confirmation or more slots filled.
10. `ToolRegistry.execute(intent, parameters, context)` — same `Map<String, ToolDefinition>` pattern, same lookup-by-string-key dispatch.
11. Speak the result: if a tool failure provided a `userMessage`, that's what gets spoken (matching the website's UX for explaining *why* something didn't happen). If TTS is on, POST the response text to `openai-proxy/audio/speech`, play the returned MP3 (needs an audio-playback package — see below).
12. State → `idle`.

## Prompt reuse strategy

`prompt.ts` is TypeScript and can't be imported into a Dart project directly, so it must be **ported as text**, not re-derived from a description of what it does. Concretely:
- Copy the actual prompt strings (base prompt, guest-tier section, authenticated-tier section — admin section omitted since admin is out of scope) into a Dart file (`lib/services/voice_assistant_prompt.dart`) as close to character-for-character as licensing/formatting allows, adjusting only the parts that describe *tools available* (since Flutter's tool set is a subset of the website's).
- Keep the exact same required JSON output envelope the website enforces, so response-parsing logic can be a direct line-for-line port of the website's `parseResponse()`.
- Keep the exact same intent *names* for every tool that's in scope (`navigate`, `search_properties`, `compare_properties`, the in-scope Tier-2 intents), so the model's behavior doesn't need to be re-tuned — it already knows how to use these intents from being trained/tested against this exact prompt on the website.
- This is a **content port**, not a redesign — the goal is that a user saying the same sentence to either client gets the same intent classification.

## Tool registry design

Same shape as the website's, translated to Dart:

```
class ToolContext {
  final void Function(String route, {Object? arguments}) navigate;
  final String? userId;
  final String? userRole;
  final String? userType;
}

class ToolResult {
  final bool success;
  final Object? data;
  final String? error;
  final String? userMessage;
}

class ToolDefinition {
  final String name;
  final String description;
  final Future<ToolResult> Function(Map<String, dynamic> params, ToolContext ctx) execute;
}

class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};
  void register(ToolDefinition tool) => _tools[tool.name] = tool;
  Future<ToolResult> execute(String name, Map<String, dynamic> params, ToolContext ctx) async { ... }
}
```

**Initial tool set** (one Dart file per category, mirroring the website's file-per-category convention):
- `navigationTool.dart` — the `navigate` intent.
- `searchTools.dart` — `search_properties`, `compare_properties`.
- `accountTools.dart` — `view_my_profile`, `show_saved_properties` (maps to the existing Shortlist screen), `show_notifications`, `my_visit_bookings` (maps to the existing Visits screen).
- `utilityTools.dart` — `confirm`/`unknown` no-op safety nets (required by the dispatch gate logic itself).

## Navigation by voice — Flutter mechanism

Direct translation of `resolveRoute()`:
- A `resolveRoute(String raw, {String? userRole})` Dart function maps the model's requested destination through, in order: known virtual concepts relevant to this app (e.g. "search" → `AppConstants.searchScreen`, "my visits" → `AppConstants.visitsScreen`), then exact known paths (checked against `AppConstants`'s existing route-name constants), then dynamic paths already carrying an id (`/property-detail` with a `propertyId` argument), falling back to Home.
- `ctx.navigate` is backed by a single `GlobalKey<NavigatorState>` held by the app (or `Navigator.of(context)` captured from wherever `VoiceAssistantProvider` is instantiated at the app root, alongside the other providers in `main.dart`) — the Flutter equivalent of the website binding `useNavigate()` once and passing the closure down.
- No admin-route backstop is needed since no admin routes are reachable in this app at all.

## Property search + filters by voice — Flutter mechanism

This is the part of the plan with the highest-confidence design, because the underlying pipeline it reuses was already built and already debugged earlier in this project:

- `search_properties` tool: parse the model's `parameters` (city, property_type, listing_type, min_price, max_price, bedrooms — same field names the website's prompt already teaches the model to use) and apply them via the **existing** `FilterProvider` setters (`setCities`, `setCategory`, `setListingType`, `setBudgetRange`, `setBhk`), then call the **existing** `PropertyProvider.runSearch(filterProvider.toQueryParams(), reset: true)`, then navigate to `SearchResultsScreen`.
- This is a direct parallel of the website's own "pure deep-link, zero duplicated query logic" pattern (§8 of the analysis) — the voice tool never talks to Supabase itself, it only sets state that the existing, already-correct search pipeline consumes. Filters set by voice and filters set by tapping chips are indistinguishable to the rest of the app.
- `compare_properties`: navigate to the existing compare screen.
- Because this reuses `FilterProvider`/`PropertyProvider` exactly, every bug fix already made to search/filtering (subtype matching, map sync, near-me) automatically applies to voice-driven search too — there is no separate code path to keep in sync.

## Context-aware conversations

- `ConversationHistoryStore`: a ring buffer of the last 20 turns (matching the website's `MAX_HISTORY`), persisted via `shared_preferences` (already a dependency), keyed so it resets whenever the signed-in user changes — a direct port of `conversationManager.ts`.
- Assistant turns are stored with their full JSON (not just the spoken sentence) and replayed to the model on later turns exactly as the website does — this is what makes multi-turn slot-filling work (e.g. the model asking a follow-up question and remembering what was already said).

## Speech-to-text / text-to-speech

**Recommended approach for this feature specifically: reuse the website's OpenAI-audio-endpoint pattern (`openai-proxy/audio/transcriptions` and `/audio/speech`), not the existing on-device `speech_to_text` package.** Reasoning: the user's stated requirement is to reuse existing AI APIs/Edge Functions, and this is the approach that does that — it also guarantees the same transcription quality/behavior as the website rather than introducing a second, different STT engine for the same product. This does mean new capability needs to be added to the Flutter app (see below); it is not free, and is flagged as the single largest new-dependency decision in this plan.

**New dependencies needed** (none exist in `pubspec.yaml` today):
- An audio-recording package (equivalent of `MediaRecorder`) to capture a microphone clip as an uploadable file/blob.
- An audio-playback package (equivalent of the browser `Audio` element) to play the MP3 bytes returned by `/audio/speech`. (`video_player` exists in this app but is video-oriented; a dedicated audio-playback package is cleaner.)
- Silence-detection (VAD) logic ported from the website's RMS-energy approach needs an audio-samples-access API from whichever recording package is chosen — this is the single most fiddly piece to get right and should be prototyped early, not left to the end.

## Relationship to the existing `VoiceSearchService` (on-device `speech_to_text`)

Left as-is, unchanged. It's a different, smaller feature — one-shot dictation into the Search screen's text box, evaluated and shipped separately from this plan. This plan's `VoiceIOService` is new and separate. If, after implementation, having two different voice-input mechanisms in the app feels redundant, that's a product decision for a follow-up review — not something to pre-resolve here by guessing.

## Files anticipated (naming/responsibility only — no code yet)

| File | Responsibility |
|---|---|
| `lib/models/agent_response.dart` | The `AgentResponse`/`ToolResult`/`ToolContext`/`ConversationTurn` types |
| `lib/services/voice_assistant_prompt.dart` | Ported system-prompt text + `buildSystemPrompt()` |
| `lib/services/ai_conversation_service.dart` | Builds the chat-completion request, calls `openai-proxy/chat/completions`, parses `AgentResponse` |
| `lib/services/voice_io_service.dart` | Audio capture + `/audio/transcriptions` + `/audio/speech` playback |
| `lib/services/conversation_history_store.dart` | `shared_preferences`-backed ring buffer, port of `conversationManager.ts` |
| `lib/tools/tool_registry.dart` | The `Map<String, ToolDefinition>` dispatcher |
| `lib/tools/navigation_tool.dart` | `navigate`, `resolveRoute()` |
| `lib/tools/search_tools.dart` | `search_properties`, `compare_properties` |
| `lib/tools/account_tools.dart` | `view_my_profile`, `show_saved_properties`, `show_notifications`, `my_visit_bookings` |
| `lib/tools/utility_tools.dart` | `confirm`, `unknown` |
| `lib/providers/voice_assistant_provider.dart` | The state machine + `processText()` turn pipeline |
| `lib/widgets/voice_assistant_button.dart` | The floating action button |
| `lib/widgets/voice_assistant_sheet.dart` | The modal bottom sheet UI (status, transcript, confirmation banner, chat history, quick commands) |
| `lib/widgets/conversation_history_list.dart` | Chat-bubble rendering |

## Open decisions to confirm before implementation

1. **STT/TTS approach** — this plan recommends reusing `openai-proxy`'s audio endpoints (matches the "reuse existing APIs" requirement, but needs two new packages and non-trivial VAD porting). The alternative is reusing the already-built on-device `speech_to_text`/`VoiceSearchService` for capture (faster to build, already proven in this app, but a different STT engine than the website uses, and doesn't touch the audio Edge Function endpoints at all). Confirm which before implementation starts.
2. **RAG grounding** (`ai-knowledge` Edge Function) — include in v1, or defer? It's additive and non-blocking (the website itself degrades silently to "no grounding" on failure), so it can safely be a fast-follow rather than a v1 requirement.
3. **Exact Tier-2 tool list** — the four listed above are a reasonable starting set given what already exists as real screens in this app; confirm nothing else (e.g. `open_chat`, if/when messaging exists in Flutter) should be added or removed.
4. **UI pattern** — a modal bottom sheet (recommended, standard Flutter mobile pattern) vs. a full-screen assistant view. Bottom sheet keeps the rest of the app reachable underneath, mirroring the website's non-modal side panel intent.

## Verification plan (once implementation is approved and done)

- Tap the assistant button from at least three different screens; confirm it's globally reachable, not screen-scoped.
- Say/type "search for 2 bhk flats in Noida under 50 lakhs" — confirm it lands on Search Results with those exact filters applied (checkable via the filter chips showing the right values, matching how manual filtering already displays them).
- Say "take me to my saved properties" / "show my visits" — confirm navigation lands on the correct existing screen.
- Have a multi-turn exchange (e.g. assistant asks a clarifying question, user answers) — confirm the second turn correctly carries forward what was said in the first.
- Trigger an error path (e.g. deny microphone permission) — confirm a clear, non-crashing message is shown, matching the "no automatic retry, always surface the failure" behavior documented for the website.
- Confirm nothing in `propcid-main/` or Supabase changed as part of this work.
