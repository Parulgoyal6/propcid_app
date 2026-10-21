# PropCID Website — AI Voice Assistant: Architecture Analysis

**Scope of this document:** the React website's AI Voice Assistant (`propcid-main/src/voice-agent/*` and its direct dependencies). This is a read-only analysis — no code was modified to produce it. All claims are cited with file paths (relative to `propcid-main/`) and line numbers from the actual source, not inferred from naming conventions.

**Two stale-documentation discrepancies found and flagged inline below** (the repo's own `docs/ai-assistant/README.md` no longer matches the code in two places), plus one internal file-naming inversion (`authTool.ts` vs `adminTool.ts`) that's easy to misread.

---

## 1. Overall architecture

The voice assistant is a **globally-mounted, tap-to-talk conversational agent** — not a page-scoped widget. It consists of five layers:

```
UI layer            VoiceAgentButton (FAB) + VoiceAgentPanel (side panel) + ConversationHistory + VoiceWaveform
                                         │
Orchestration layer  VoiceAgentContext (React Context, useReducer state machine, processText() turn pipeline)
                                         │
         ┌───────────────────┬──────────┴───────────┬────────────────────┐
         ▼                   ▼                       ▼                    ▼
   speechService       voiceAgentService        toolRegistry          conversationManager
   (STT + TTS)         (the "brain" — builds     (Map<name,Tool>,      (session-storage
                        the LLM request,          dispatches by        ring-buffer of
                        parses its JSON reply)     intent string)       last 20 turns)
         │                   │                       │
         ▼                   ▼                       ▼
   openai-proxy         openai-proxy            10 tool-definition files (navigationTool,
   /audio/transcriptions /chat/completions       authTool, adminTool, listingTools, crmTools,
   /audio/speech         (model: gpt-5-mini,      cmsTools, videoTools, searchTools,
   (Edge Function)       server-controlled)       utilityTools, dashboardTools)
                                                        │
                                          each tool does ONE of: ctx.navigate(path) |
                                          direct supabase.from(table).select/insert/update |
                                          sessionStorage stash + navigate (deferred prefill)
```

**Where it lives in the app:** `VoiceAgentProvider` wraps the entire `<Routes>` tree in `src/App.tsx:126-451`, with `<VoiceAgentButton/>` and `<VoiceAgentPanel/>` rendered as siblings right after it (`App.tsx:449-450`). It is available on every route — public, authenticated, and admin — with tier-appropriate behavior handled entirely by **prompt content** and **per-tool RBAC checks**, not by conditionally mounting the component.

**Activation:** purely tap-to-talk. No wake word, no continuous listening. The mic only starts recording when the user taps the floating button or the panel's mic button (`VoiceAgentButton.tsx:29-33`, `VoiceAgentPanel.tsx:142-148`). A text-input fallback and clickable "quick command" chips let a user drive it without speaking at all.

---

## 2. Data flow (one full turn, start to finish)

1. **User taps mic** → `startListening()` (`context/VoiceAgentContext.tsx:421-452`) guards `agentState === 'idle'`, cancels any playing TTS, sets state to `'listening'`, calls `speechService.startListening(...)`.
2. **Recording** → `MediaRecorder` captures mic audio; a Web Audio API RMS-based silence detector auto-stops after ~1.5s of quiet (or a 15s hard cap). State stays `'listening'` the whole time — there is no separate "transcribing" visual state.
3. **Transcription** → on stop, the recorded blob is POSTed as `multipart/form-data` to `openai-proxy/audio/transcriptions` (OpenAI `gpt-4o-mini-transcribe`). The returned text triggers `onFinal(text)` → `processText(text)`.
4. **`processText` begins** (`VoiceAgentContext.tsx:205-417`) → state → `'processing'`. The user's turn is appended to `conversationManager` (session-storage-backed) and, best-effort, to a Supabase-backed history table.
5. **Context assembly**:
   - `history` = every prior turn from `conversationManager` except the one just added.
   - `systemPrompt` = built **fresh every turn** by `buildSystemPrompt()` (`prompt.ts`) — assembles a shared base plus exactly one auth tier (guest / authenticated / admin-by-role) plus, optionally, an "autonomous mode" section.
   - `knowledgeContext` (RAG) = if enabled and the utterance isn't a trivial "yes/no", `retrieveContext(userText)` calls the `ai-knowledge` Edge Function and returns a formatted text block of retrieved knowledge snippets.
   - `memoryContext` = long-term memory (preferred city, recent searches, last-viewed property) formatted as text.
   - Both context blocks are concatenated as plain text onto the system prompt string — **not** sent as separate message roles or tool outputs.
6. **LLM call** → `processVoiceCommand(userText, history, systemPrompt, groundingContext)` (`voiceAgentService.ts`) builds an OpenAI chat-completions request (`response_format: json_object`) and POSTs it to `openai-proxy/chat/completions`. The Edge Function stamps in the real model (`gpt-5-mini` by default) and the real API key server-side, then relays to OpenAI.
7. **Response parsing** → the model's `message.content` (a JSON string) is parsed into a strict `AgentResponse` shape: `{ intent, parameters, response, needs_confirmation, missing_fields, complete }`. Malformed JSON silently falls back to `intent: 'unknown'`.
8. **Confirmation resolution** → if the new response is the user saying "yes" to a previously staged risky/expensive action, the *original* staged intent/parameters are substituted back in for execution.
9. **Dispatch gate** (`shouldExecuteTool`) → decides whether to actually run a tool at all (skipped for `unknown`/pure-Q&A intents, or if the turn still needs confirmation / more slots filled).
10. **Tool execution** → `toolRegistry.execute(intent, parameters, toolCtx)` looks up the intent name in a `Map`, calls its handler with a context object (`{ navigate, userId, userRole, userType, isAdmin, isSuperAdmin, ... }`), and returns `{ success, data?, error?, userMessage? }`. Every tool does one of: pure `ctx.navigate(path)`, a direct Supabase table read/write, or a session-storage stash followed by a navigate (deferred prefill for flows voice can't fully complete, like photo upload).
11. **Speak the result** → if a tool failure provided a `userMessage`, that overrides what gets spoken (so users hear *why* something didn't happen). If text-to-speech is enabled, state → `'speaking'`, the response text is POSTed to `openai-proxy/audio/speech` (OpenAI `gpt-4o-mini-tts`), and the returned MP3 is played via an `<audio>` element.
12. **Back to idle** → state resets to `'idle'` unconditionally once speech finishes (or immediately if TTS is off/muted).

Conversation history is capped at the last 20 turns and is reset whenever the signed-in user changes, so one user's context never leaks into the next session. Critically, assistant turns are replayed to the model on later turns using their **full structured JSON** (`rawJsonText`), not just the spoken sentence — this is what lets multi-turn slot-filling (e.g. building up a `create_listing` command across several turns) work.

---

## 3. Which AI model is used

**OpenAI**, model **`gpt-5-mini`** by default, controlled entirely server-side:

```ts
// supabase/functions/openai-proxy/index.ts:33-34
const CHAT_MODEL = Deno.env.get("CHAT_MODEL") || "gpt-5-mini";
const REASONING_EFFORT = Deno.env.get("REASONING_EFFORT") || "minimal";
```
The client's request body never specifies a model — the Edge Function overwrites/stamps it in before relaying to OpenAI. Two other OpenAI models are used for voice I/O specifically (not the decision brain): **`gpt-4o-mini-transcribe`** for STT and **`gpt-4o-mini-tts`** for TTS (documented in `speechService.ts`'s own header comment).

**Gemini is not used for decision-making.** It only appears one layer removed: the separate `ai-knowledge` RAG Edge Function uses **`gemini-embedding-001`** (768-dim, matching the pgvector column) to embed and rank knowledge-base queries. The voice agent calls that function's `"query"` action and receives back plain retrieved-text chunks — it never calls Gemini directly, and never invokes that function's `"answer"` action (which would use `gemini-2.5-flash` to generate a fully Gemini-authored response) at all.

**Documentation/dead-code discrepancy:** comments inside `aiProvider.ts` and `listingTools.ts` reference client env vars (`VITE_OPENAI_BRAIN_MODEL`, `VITE_OPENAI_LISTING_MODEL`) that **do not exist anywhere in the actual code** — a repo-wide grep found only the comments, never a real `import.meta.env` read. The model is 100% server-controlled; treat those comments as stale.

---

## 4. Which backend APIs are called

Exactly **two** Supabase Edge Functions are reachable from the voice agent (confirmed by grepping the entire `src/voice-agent/` tree and its direct dependencies):

| Endpoint | Called from | Purpose |
|---|---|---|
| `openai-proxy/chat/completions` | `voice-agent/services/voiceAgentService.ts:87-91` | The decision brain — sends system prompt + history + new utterance, gets back JSON `AgentResponse` |
| `openai-proxy/audio/transcriptions` | `voice-agent/services/speechService.ts:212-216` | Speech-to-text (multipart audio upload) |
| `openai-proxy/audio/speech` | `voice-agent/services/speechService.ts:238-246` | Text-to-speech (returns MP3 bytes) |
| `ai-knowledge` (action: `"query"`) | `services/rag/knowledgeService.ts:57-59`, called from `VoiceAgentContext.tsx:242` | RAG retrieval — embeds the query (Gemini) and returns ranked, role-scoped knowledge chunks as plain text |

All three `openai-proxy` calls are plain `fetch()` (not the Supabase JS client's `functions.invoke`), authenticated via `apikey: <anon key>` + `Authorization: Bearer <session JWT, or anon key for guests>` — built by a shared `proxyAuthHeaders()` helper (`services/openaiProxy.ts:29-40`). The real OpenAI API key is injected server-side inside the Edge Function and never reaches the browser. `ai-knowledge` is called via `supabase.functions.invoke(...)` instead.

**No other backend endpoint is called from anywhere under `src/voice-agent/`.** Every listing/CRM/CMS write goes straight to Postgres via the standard Supabase JS client (`@/integrations/supabase/client`) — there is no dedicated "voice backend."

---

## 5. How speech is converted to text (and back)

**Not the browser's Web Speech API.** This is a recorded-audio-upload approach, entirely OpenAI-powered:

```ts
// voice-agent/services/speechService.ts:1-10 (the file's own header comment)
/**
 * Voice I/O powered entirely by OpenAI:
 *   Speech to Text — gpt-4o-mini-transcribe  (POST /audio/transcriptions)
 *   Text to Speech — gpt-4o-mini-tts         (POST /audio/speech)
 *
 * STT records the mic with MediaRecorder and auto-stops after a short pause of
 * silence, then sends the clip to OpenAI for transcription. There is NO browser
 * Web Speech fallback and no other provider.
 */
```

- **Capture**: `navigator.mediaDevices.getUserMedia({audio:true})` → `MediaRecorder` → chunks accumulated in `ondataavailable`.
- **Auto-stop (VAD)**: a Web Audio `AnalyserNode` computes RMS energy each animation frame; if it stays below a `0.012` threshold for `1500ms` after speech was detected, recording stops automatically. Hard cap 15 seconds; minimum clip length 400ms (guards against accidental taps).
- **Transcription**: on stop, the blob is sent as multipart form data (`language: 'en'`) to `openai-proxy/audio/transcriptions`.
- **No true interim results**: because this isn't streaming recognition, there's only ever one "final" transcript per utterance — the UI's `onInterim('')` call at the very start exists purely to clear stale text, not to show live partial words.
- **Speech output**: the assistant's response text is POSTed as JSON to `openai-proxy/audio/speech`, the MP3 response bytes become a `Blob` URL, and playback happens through a plain `new Audio(url)` element (not `speechSynthesis`).

**Documentation discrepancy:** `docs/ai-assistant/README.md` (line 132) still describes the pipeline as `mic → speechService (Web Speech) → transcript` — this is out of date. The actual, current implementation is the OpenAI MediaRecorder pipeline above, confirmed directly in `speechService.ts`'s own header comment and its VAD/recorder code.

---

## 6. How the AI decides which action to perform

**This is not OpenAI's function-calling / tool-calling API.** No `tools`/`functions`/`tool_choice` field is ever included in the request body — confirmed by reading the exact payload construction:

```ts
// voice-agent/services/voiceAgentService.ts:78-85
const body = {
  messages: buildOpenAIMessages(history, userText, systemPrompt),
  response_format: { type: 'json_object' },
  max_completion_tokens: 4096,
};
```

Instead, it's a **prompt-engineered JSON-intent classification scheme**:

1. `prompt.ts` (715 lines) describes every available intent in natural-language prose, tiered by auth level, and instructs the model to *always* reply with one fixed JSON envelope:
   ```json
   {
     "intent": "<intent_name>",
     "parameters": { ...fields },
     "response": "<what to say out loud>",
     "needs_confirmation": false,
     "missing_fields": [],
     "complete": true
   }
   ```
2. The model picks an `intent` string from the ~60-entry `Intent` union type it was taught about in the prompt, and fills `parameters` itself (in the shape the prompt described for that intent).
3. The client parses this JSON and uses the `intent` string as a **direct lookup key** into the tool registry — `toolRegistry.execute(intent, parameters, ctx)`.
4. `ToolDefinition` objects have **no JSON-schema `parameters` field** at all — only a free-text `description`, confirming that no machine-readable schema is ever given to the model; the correspondence between intent names and tool names is maintained by hand/convention across `prompt.ts` and the tool files, not enforced by any shared schema.

Before dispatch, a gate function decides whether to execute anything at all:
```ts
// context/VoiceAgentContext.tsx:190-201
const shouldExecuteTool = (response, ws) => {
  if (response.intent === 'unknown') return false;
  if (response.intent === 'ask_platform') return false;
  if (response.intent === 'confirm') return response.parameters.response === 'yes' && ws.pendingConfirmation;
  if (!response.complete) return false;
  if (response.needs_confirmation) return false;
  return true;
};
```
So multi-turn "slot filling" (e.g. building up a `create_listing` command across turns) is done by the model itself setting `complete: false` and `missing_fields: [...]` until it has enough information, with the client persisting the in-progress intent/parameters into `workflowState` between turns.

---

## 7. How navigation is triggered

**No global/singleton navigate hack.** `useNavigate()` (react-router) is called exactly once, correctly, inside the `VoiceAgentProvider` component (`context/VoiceAgentContext.tsx:137`). That bound `navigate` function is packed fresh into a plain `ToolContext` object on every turn and passed into whichever tool's `execute(params, ctx)` runs — tool files are ordinary non-component modules that never call the hook themselves; they just receive `ctx.navigate` as a dependency.

The `navigate` tool itself:
```ts
// voice-agent/tools/navigationTool.ts:134-143
toolRegistry.register({
  name: 'navigate',
  description: 'Navigate to any route or page... Accepts an exact path or a natural-language destination, resolved via the RAG route index.',
  execute: async (params, ctx) => {
    const rawRoute = (params.route as string) || '/';
    const resolved = resolveRoute(rawRoute, ctx.userRole);
    ctx.navigate(resolved);
    return { success: true, userMessage: `Navigated to ${resolved}` };
  },
});
```

`resolveRoute()` is a multi-stage resolution pipeline, in order:
1. **Role-aware virtual concepts** — "dashboard"/"analytics"/"crm"/"cms"/"seo" resolve to *different* concrete routes depending on the caller's role.
2. **Exact known path** — checked against a route-index-derived set, plus an RBAC `canAccess(path, tier)` check.
3. **Concrete dynamic paths** already carrying an id (`/property/:id`, `/admin/...`) — admin-prefixed ones are blocked for non-admin tiers.
4. **RAG fallback** — `resolveConcept(raw, tier)` looks the phrase up in the same route index that seeds the knowledge base's vector store, so the model can target pages it was never explicitly hard-coded to know about.
5. Default to `/`.

A final RBAC backstop redirects a plain `admin` role away from `/super-admin/*` even if resolution somehow produced that path — mirroring the actual page-level guard, so voice can't accidentally route around it. Several other tool files (`crmTools.ts`, `cmsTools.ts`, `adminTool.ts`) reuse the same `resolveRoute` helper to compute role-correct destinations before navigating.

---

## 8. How search commands are handled

**Pure deep-link — zero duplicated query logic.** The entire `searchTools.ts` file is 38 lines and contains no `supabase.from(...)` call at all:

```ts
// voice-agent/tools/searchTools.ts (search_properties, abridged)
execute: async (params, ctx) => {
  const sp = new URLSearchParams();
  if (params.city)          sp.set('city', String(params.city));
  if (params.property_type) sp.set('category', String(params.property_type).toLowerCase());
  if (params.listing_type)  sp.set('type', String(params.listing_type));
  if (params.min_price)     sp.set('minPrice', String(params.min_price));
  if (params.max_price)     sp.set('maxPrice', String(params.max_price));
  if (params.bedrooms)      sp.set('bedrooms', String(params.bedrooms));
  ctx.navigate(sp.toString() ? `/search?${sp}` : '/search');
  return { success: true, userMessage: `Searching for ${/* built from params, not from any query result */}` };
},
```

The AI never sees actual matching properties in-conversation — the spoken confirmation ("Searching for 2 BHK apartments in Gurgaon") is generated purely from the *request* parameters, not from any result set. All real filtering/querying happens exclusively inside `Search.tsx`, which reads these same URL params (`city`, `category`, `type`, `minPrice`, `maxPrice`, `bedrooms`) on mount. `compare_properties` is even simpler — it's a single unconditional `ctx.navigate('/compare')`.

---

## 9. How property commands are handled

Property/listing tools live in `listingTools.ts` (293 lines: `create_listing`, `update_listing`, `delete_listing`, `publish_listing`, `save_draft`) and hit `properties` directly via the standard Supabase client — no Edge Function involved.

**`create_listing`** is the most involved, and demonstrates the general pattern (direct-write-with-navigate-fallback):
1. Role gate — `canCreate('property', ctx.userType)` blocks builder accounts.
2. If required fields (category, deal, price, city) aren't all present yet, it **doesn't** write to the DB — it stashes what it has to `sessionStorage['va_listing_draft']` and navigates to `/post-property` so the manual wizard can pick up where voice left off.
3. If slots are complete, it does a real `supabase.from('properties').insert(payload).select('id, title').single()` (status `inactive`, `approval_status: 'pending'` — a genuine draft row, not a fake response).
4. On a DB error, it falls back to the same wizard-with-prefill path rather than failing outright.
5. On success, it navigates again — to the media-upload step of the just-created listing, or to the manage-properties list — because voice can't upload photo files itself.

**`update_listing`**/`publish_listing`/`delete_listing`: find the caller's own listing by a fuzzy title match (scoped `.eq('user_id', ctx.userId)`), then a direct `.update(...)`/`.delete()` on `properties`, followed by `ctx.navigate('/manage-properties')`.

**`schedule_visit`** (in `utilityTools.ts`) is a hybrid: a read-only lookup to find the named property, then `ctx.navigate('/property/{id}')` (or a search fallback if not found) — the actual visit-booking write happens on that property page's own UI, not from voice directly.

This "stash to sessionStorage + navigate to the real form/page" pattern recurs across nearly every write-capable tool category (listings, CMS articles, video uploads, admin actions) — it's the consistent answer to "the model decided to do X, but X requires a file upload / a complex form / a destructive confirmation UI voice shouldn't perform blind."

---

## 10. How the tool registry works

`tools/registry.ts` (37 lines) is a minimal class wrapping a plain `Map<string, ToolDefinition>`:

```ts
class ToolRegistry {
  private readonly tools = new Map<string, ToolDefinition>();
  register(tool: ToolDefinition): void { this.tools.set(tool.name, tool); }
  async execute(name, params, ctx): Promise<ToolResult> {
    const tool = this.tools.get(name);
    if (!tool) return { success: false, error: `Tool "${name}" is not registered.` };
    try { return await tool.execute(params, ctx); }
    catch (err) { return { success: false, error: err instanceof Error ? err.message : 'Tool execution failed' }; }
  }
  has(name: string): boolean { return this.tools.has(name); }
  getAll(): ToolDefinition[] { return Array.from(this.tools.values()); }
}
export const toolRegistry = new ToolRegistry();
```

**Registration is a side effect of module import**, not an explicit build step. `voice-agent/index.ts` imports all 10 tool files purely for their side effects:
```ts
import './tools/navigationTool';
import './tools/dashboardTools';
import './tools/listingTools';
import './tools/crmTools';
import './tools/cmsTools';
import './tools/videoTools';
import './tools/searchTools';
import './tools/utilityTools';
import './tools/authTool';
import './tools/adminTool';
```
Each file calls `toolRegistry.register({...})` at its top level (module load time), so simply importing `voice-agent/index.ts` once (which `App.tsx` does, indirectly, by importing `VoiceAgentProvider` from it) populates the entire registry before the app renders.

**`ToolDefinition` shape:**
```ts
interface ToolContext {
  navigate: (path: string) => void;
  userId?: string; userRole?: string; userType?: string;
  displayName?: string; profileCity?: string;
  isSuperAdmin?: boolean; isAdmin?: boolean;
}
interface ToolResult<T = unknown> { success: boolean; data?: T; error?: string; userMessage?: string; }
interface ToolDefinition<P = Record<string, unknown>> {
  name: string;
  description: string;
  execute: (params: P, ctx: ToolContext) => Promise<ToolResult>;
}
```
No JSON-schema `parameters` field — consistent with §6's finding that the model is never given a machine-readable tool schema, only prose in the system prompt.

**Naming inversion worth flagging**: despite the filenames, `authTool.ts` actually registers the **Tier-1 admin** intents (`list_users`, `ban_user`, `verify_user`, property/article moderation, etc. — all via a shared `registerAdminNav()` helper), while `adminTool.ts` registers the **Tier-2 authenticated-user** intents (`my_properties_summary`, `view_my_profile`, `open_chat`, `post_content`, `delete_account`, etc.). The two files' names are effectively swapped relative to their content — worth knowing before searching the codebase by filename.

**Registered-tool count**: raw `toolRegistry.register()` call sites total ~40 across the 10 files, but `adminTool.ts`'s `registerAdminNav()` helper itself calls `register()` internally and is invoked ~14 additional times for simple admin nav intents — so the true count is somewhat higher than a naive grep suggests, consistent with the "~40 tools" figure from earlier scoping.

---

## 11. Permission/role gating (relevant context for §12)

Three independent layers, from the code's own comments:
1. **Prompt-assembly level (primary guarantee)** — the admin section of the system prompt is only appended if the caller's role is an admin role. Comment: *"Admin intents are NEVER injected for non-admin users — the model cannot even parse commands it has never been shown."*
2. **Tool-execution level** — `canCreate()` checks before content-creation tools; explicit `ctx.isSuperAdmin` checks before the two most sensitive admin tools; the navigation RBAC backstop in §7.
3. **Database level (the real backstop)** — Postgres RLS policies (e.g. `properties` requires `auth.uid() = user_id` for insert/update/delete) reject any write outside the caller's own scope regardless of what the client-side layers do.

---

## 12. Which parts can be reused in Flutter (conceptually) vs. which are web-specific

### Reusable **concepts** (the architecture pattern, not the code — everything here is TypeScript/React and cannot be ported directly, but the *design* translates well)

- **The JSON-intent scheme itself** — since it's plain prompt engineering against a JSON-mode chat completion (not React/browser-specific), the exact same request/response contract (`{intent, parameters, response, needs_confirmation, missing_fields, complete}`) can be replicated from Dart: build a system prompt, POST to the *same* `openai-proxy/chat/completions` Edge Function (already reachable from Flutter via `Supabase.instance.client.functions.invoke`, exactly as this app's `AiSearchService` already does), parse the same JSON shape.
- **The tool-registry pattern** — a `Map<String, ToolDefinition>` populated at startup, dispatched by intent-name string, is a plain data-structure pattern with no web dependency; a Dart equivalent (`Map<String, Future<ToolResult> Function(Map<String,dynamic>, ToolContext)>`) is straightforward.
- **The "navigate is just a function passed into a context object" pattern** — translates directly to Flutter: a `ToolContext` carrying a `void Function(String route) navigate` (backed by `Navigator.pushNamed`) instead of react-router's `useNavigate()`.
- **The direct-Supabase-write-with-fallback pattern** for property/listing commands (try a direct write if enough info is present; otherwise stash partial state and hand off to the existing manual form) — this is backend-and-framework-agnostic and maps cleanly onto Flutter's own screens/providers.
- **The three-layer permission model** (prompt exposure → tool-level checks → RLS backstop) — directly applicable; RLS enforcement is already shared infrastructure.
- **The RAG grounding call** (`ai-knowledge` Edge Function, action `"query"`) — a plain HTTP/Edge-Function call, callable from Flutter exactly as from web.
- **The conversation-history-as-JSON replay technique** (sending the model's own prior structured JSON output back to it, not just the spoken text) — is what makes multi-turn slot-filling work, and is a prompt/data-shape decision, not a web API dependency.

### Web-specific (cannot be reused as-is; would need a genuinely different implementation on mobile)

- **Speech-to-text capture**: `MediaRecorder` + Web Audio `AnalyserNode`-based silence detection are browser APIs. A Flutter equivalent already exists in this codebase for the Search screen's Voice Search feature (`speech_to_text` package, on-device native STT) but that is architecturally *different* from this website's approach (recorded-blob-upload-to-OpenAI vs. on-device streaming recognition) — porting "the same way" would mean adding audio-recording + multipart-upload plumbing in Flutter, which nothing in this app currently has.
- **Text-to-speech playback**: browser `Audio` element playing an MP3 Blob URL — Flutter would need an audio-playback package (e.g. `just_audio`/`audioplayers`), not present in this app currently.
- **`useNavigate()` / react-router** itself — the *pattern* (inject a navigate closure into a context object) is reusable, but the concrete hook and route-string conventions are React-Router-specific and would be re-expressed via `Navigator`/named routes in Flutter.
- **`sessionStorage`-based drafts** (`va_listing_draft`, `va_admin_*`, etc.) — browser-only storage API; a Flutter port would use `shared_preferences` (already a dependency in this app) or in-memory provider state instead.
- **The floating-button + slide-in-side-panel UI** (`VoiceAgentButton`/`VoiceAgentPanel`/`ConversationHistory`/`VoiceWaveform`) — these are React/Tailwind components; a Flutter voice-assistant UI would need to be built from scratch as widgets, though the *information architecture* (status bar, live transcript, confirmation banner, workflow banner, scrollable chat bubbles, quick-command chips) is a reasonable reference design.
- **Admin/CRM/CMS/video/dashboard tool categories** — these were already explicitly scoped *out* of the Flutter app's mobile parity effort (back-office/power-user tooling stays web-only per earlier scoping decisions), so those ~30 of the ~40 registered tools are not relevant to a Flutter voice assistant at all; only `navigate`, `search_properties`, `compare_properties`, and a handful of Tier-2 authenticated tools (view profile, saved properties, notifications, visit bookings) would be in scope for a mobile equivalent.

---

## Summary table

| Question | Answer |
|---|---|
| AI model (decision brain) | OpenAI `gpt-5-mini` (server-controlled via `CHAT_MODEL` secret) |
| AI model (STT) | OpenAI `gpt-4o-mini-transcribe` |
| AI model (TTS) | OpenAI `gpt-4o-mini-tts` |
| AI model (RAG embeddings) | Gemini `gemini-embedding-001` (768-dim) — retrieval only, not decision-making |
| Tool-calling mechanism | None used — plain JSON-mode chat completion + prompt-engineered intent classification |
| Edge Functions called | `openai-proxy` (3 sub-paths) + `ai-knowledge` (1 action) |
| Wake word | None — tap-to-talk only |
| Interim transcripts | None — one-shot recorded-then-transcribed, not streaming |
| Tool registry | `Map<string, ToolDefinition>`, populated by import-time side effects |
| Navigation mechanism | `useNavigate()` called once in the provider, passed down as `ctx.navigate` |
| Search commands | Pure `/search?...` deep-link — no duplicated query logic |
| Property/listing commands | Direct Supabase writes with sessionStorage-stash-and-navigate fallback |
| Permission enforcement | 3 layers: prompt exposure, tool-level checks, Postgres RLS backstop |
