# Agent backend research: web search, compaction, small-model tools, feature checklist

Researched 2026-11-05 (file keeps its 2026-11-03 name). Replaces the earlier, thinner draft; its
measurements are kept where still true and marked *(earlier session)*.

**Evidence tags.** *measured* = I ran it on this machine today (RTX 4050 Laptop 6 GiB, about 1.05 GiB already
used by the desktop, Ollama 0.40.13, `OLLAMA_FLASH_ATTENTION=1` already set in
`/etc/systemd/system/ollama.service.d/override.conf`). *primary* = vendor docs or the cloned source.
*secondary* = blog / aggregator, treat as indicative.

**The repo has moved past the task brief.** Installed models are now `qwen3.5:4b`,
`huihui_ai/qwen3.5-abliterated:4b`, `huihui_ai/qwen3-abliterated:8b`, `gpt-oss:20b` (hermes3, deepseek-r1 and
minicpm-v are gone). `bin/rice_agent.py` already has 20 tools (~2,500 prompt tokens with the system prompt, per
`2026-11-04-agent-architecture.md`), a `web_search` chain (SearXNG → Ollama → DDG → Bing → Wikipedia), `web_fetch`
and compaction. Each section says what to keep and what to change.

---

## A. Free web search without a paid key

### A.1 Candidates

| Source | Key? | Free? | Verdict |
|---|---|---|---|
| **SearXNG**, self-hosted | none | yes | **Best primary if you run it.** Aggregates several engines, real JSON, hides per-engine blocks. Costs a container. |
| **DDG `html.duckduckgo.com/html/`** | none | yes | **Best zero-setup primary.** *measured*: 200 OK, 10 results. Bursts trigger a captcha page. |
| DDG `lite.duckduckgo.com/lite/` | none | yes | **Skip.** *measured*: first request from this IP returned **HTTP 202 + "Select all squares containing a duck"** while `/html/` answered normally. |
| Bing HTML | none | yes | Fallback *(earlier session, not re-run)*. Fragile markup. |
| Wikipedia REST | none (UA required) | yes | Fallback for factual queries. *measured*: works. |
| Ollama `web_search` / `web_fetch` | **yes** (`OLLAMA_API_KEY`, free Ollama account) | free, limits unpublished | Optional tier; sends queries to ollama.com. |
| Jina `r.jina.ai` (Reader) | optional | 20 RPM keyless, 500 RPM free key | Good `web_fetch` fallback for JS pages. |
| Jina `s.jina.ai` (Search) | **required** | 100 RPM with free key | Skip. *measured*: keyless → **HTTP 401** `AuthenticationRequiredError`. |
| Brave Search API | **yes + card** | **No free tier since Feb 2026**: $5 credit/month ≈ 1,000 queries | Skip. |
| Mojeek API | **yes** | Pay-as-you-go: Startup £2 / 1,000 requests, 5 q/s; trial credits on sign-up | Skip (not free). |
| Marginalia | key `public` (shared) or free key by email | yes, non-commercial (CC-BY-NC-SA 4.0) | Niche: small indie-web index, weak for news/versions. |

Sources: Ollama [docs.ollama.com/capabilities/web-search](https://docs.ollama.com/capabilities/web-search) (primary);
Jina rate table on [jina.ai/reader](https://jina.ai/reader/) (primary: Reader 20 RPM keyless / 500 free key, Search
100 RPM; search "costs a fixed number of tokens, starting from 10,000"); Brave removal
[implicator.ai](https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing/)
(secondary; existing free-plan users unaffected); Mojeek [mojeek.com/services/api.html](https://www.mojeek.com/services/api.html)
(primary pricing; trial: [community.mojeek.com](https://community.mojeek.com/t/web-search-api-trial-and-account-page-error/2655));
Marginalia [about.marginalia-search.com/article/api](https://about.marginalia-search.com/article/api) (primary:
`api2.marginalia-search.com/search?query=…`, header `API-Key: public`, shared limit, "often hits a rate limit").

### A.2 SearXNG (self-hosted)

- **Install.** No `searxng` package in the official Arch repos (*measured*: `pacman -Si searxng` → not found).
  AUR has `searxng-git` (15 votes; depends on `valkey`), `searxng-uwsgi-git`, `searxng-rama`
  ([AUR](https://aur.archlinux.org/packages/searxng-git)). Docker is simpler and you already run it for `sandbox_run`:
  ```
  mkdir -p ~/.config/rice/searxng
  docker run -d --name searxng --restart unless-stopped -p 127.0.0.1:8888:8080 \
    -v ~/.config/rice/searxng:/etc/searxng searxng/searxng
  ```
  First start writes `settings.yml`; edit, then `docker restart searxng`. (Not run here.)
- **Enable JSON** or `format=json` returns 403 ([SearXNG admin docs](https://docs.searxng.org/admin),
  [Open WebUI guide](https://docs.openwebui.com/features/chat-conversations/web-search/providers/searxng)):
  ```yaml
  use_default_settings: true
  server:
    secret_key: "<openssl rand -hex 32>"
    limiter: false          # localhost only; avoids the valkey requirement
  search:
    formats: [html, json]
  ```
- **Request.** `GET http://127.0.0.1:8888/search?q=<q>&format=json&language=en&categories=general` →
  `results[]` each `{title, url, content, engine, publishedDate?}`, plus `answers[]`, `infoboxes[]`,
  `unresponsive_engines[]` (check it: a thin list may mean engines were suspended, not a bad query).
- **RAM.** Not measured. Reports: ~180 MB under a 512 MB cap; a third-party slim image lists ~500 MiB idle with
  5 workers; some users needed `mem_limit: 1g` ([ZimaSpace](https://shop.zimaspace.com/pages/searxng-hardware-requirements),
  secondary). Budget **~300–500 MB RAM, no VRAM**; 1–2 workers is enough for one user.

### A.3 DuckDuckGo HTML: call and parse (*measured* today)

- **Request.** `POST https://html.duckduckgo.com/html/`, form `q=<query>` (optional `kl=wt-wt`), headers
  `User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0`,
  `Content-Type: application/x-www-form-urlencoded`. Use a browser UA; urllib's default UA is the classic trigger.
- **Parse.** Per result: `a.result__a` (title text, `href`) and `a.result__snippet` (**an `<a>`, not a div**).
  `href` is sometimes `//duckduckgo.com/l/?uddg=<urlencoded target>&rut=…`: take
  `parse_qs(urlparse(href).query)["uddg"][0]` and prefix `https:` on protocol-relative links. Skip `result--ad`
  blocks. With `html.parser`: on `<a class="result__a">` start collecting text until `</a>`; same for
  `result__snippet`; zip by order.
- **Block detection.** HTTP 202, body containing `anomaly` / `Select all squares`, or zero `result__a` → blocked.
  Mark DDG cold for 5 minutes and fall through; never retry in a loop.
- **Limits.** None published. DDG's terms discourage scraping; vendor claims that `/html/` is gentler than the
  `ddgs` token flow are unverified ([lucivuc](https://lucivuc.github.io/ddg-web-search/docs.html), secondary). For one
  user making a few queries an hour it is a judgment call, which is why SearXNG sits ahead of it.
- Keep the instant-answer API (`api.duckduckgo.com`) dropped.

### A.4 Wikipedia (*measured*)

- Search: `GET https://en.wikipedia.org/w/rest.php/v1/search/page?q=<q>&limit=3` → `pages[].{key,title,description,excerpt}`;
  `excerpt` holds `<span class="searchmatch">`: strip tags.
- Summary: `GET https://en.wikipedia.org/api/rest_v1/page/summary/<key>` → `extract`, `content_urls.desktop.page`.
- Send a descriptive UA, e.g. `rice-assistant/1.0 (personal desktop)`; Wikimedia blocks generic library UAs.

### A.5 Ollama's hosted web_search / web_fetch (*primary*)

- `POST https://ollama.com/api/web_search`, `Authorization: Bearer $OLLAMA_API_KEY`, body
  `{"query": str, "max_results": 1..10 (default 5)}` → `{"results":[{"title","url","content"}]}`.
- `POST https://ollama.com/api/web_fetch`, body `{"url": str}` → `{"title","content","links":[…]}`.
- Needs a free account + key; the docs give **no rate numbers**. Not local: queries leave the machine. Opt-in
  tier when `OLLAMA_API_KEY` is set (already tier 2 in `tool_web_search`); never required.

### A.6 `web_fetch`: stdlib page → ~2k tokens of clean text

1. `urllib.request.Request(url, headers={"User-Agent": <browser UA>, "Accept": "text/html,application/xhtml+xml,text/plain;q=0.8", "Accept-Language": "en"})`, `timeout=12`.
   Refuse non-http(s). Resolve the host and **refuse loopback / private / link-local IPs** (a model can be talked into
   fetching `http://127.0.0.1:11434/`); re-check on every redirect (subclass `HTTPRedirectHandler`, max 4 hops).
2. Read at most **1.5 MB**. Charset: `Content-Type` → `<meta charset>` in the first 2 KB → utf-8 `errors="replace"`.
   **Sniff** `<!doctype html` / `<html` in the first bytes too: *measured*, hypr.land sends `application/octet-stream`
   (Jina answers `422 unexpected content type` for the same page).
3. `html.parser.HTMLParser` subclass:
   - skip subtrees: `script style noscript svg template iframe canvas nav header footer aside form button select`, and
     elements whose `class`/`id` matches `cookie|consent|banner|sidebar|breadcrumb|comment|share|newsletter`;
   - if `<main>` or `<article>` exists, keep only that; else `<body>`;
   - block tags (`p div li tr h1-h6 br section pre blockquote`) emit `\n`; `h1-h3` prefix `# `; `li` prefix `- `;
     keep whitespace inside `<pre>`; keep link text, drop URLs, except a trailing `Links:` list of the first 5
     absolute links so the model can follow one;
   - keep `<time datetime>` as text **plus** the datetime attribute (GitHub shows "03 Nov" with the year only in
     the attribute) *(earlier session)*.
4. Collapse whitespace, drop short lines repeated 3+ times (menus), dedupe consecutive duplicates, title first,
   **truncate at 8,000 chars (~2,000 tokens)** at a paragraph boundary and append
   `[truncated: N more chars; call web_fetch with offset=8000]`.
5. Fallbacks: stdlib → if text < 300 chars (JS app) `GET https://r.jina.ai/<url>` with `Accept: text/plain`,
   `X-Return-Format: markdown`, `X-Timeout: 10` (keyless 20 RPM) → sandbox Chromium. PDFs: say so, don't parse.

### A. Recommendation

```
web_search chain (first success wins; 6 s per tier; return top 5 as "title - url - snippet<=200ch"):
  0. cache  (query lowercased+trimmed, 10 min TTL, 50 entries)
  1. SearXNG  http://127.0.0.1:8888/search?q=...&format=json    when RICE_SEARXNG_URL set or a 300 ms probe of :8888 answers
  2. Ollama   POST https://ollama.com/api/web_search              only when OLLAMA_API_KEY is set
  3. DDG HTML POST https://html.duckduckgo.com/html/              skipped for 5 min after a block page
  4. Bing HTML (li.b_algo; /ck/a?...&u=a1<base64url>)             earlier session; re-verify before relying
  5. Wikipedia REST search + summary                              always available; label "(Wikipedia)"
Throttle: >= 1.5 s between DDG/Bing hits; 1 retry after 2 s only on timeout, never on a block page.
Result tail: "Next: call web_fetch on the best URL if the snippets don't answer it."  (earlier: hermes 0/3 -> 2/3 reading pages)
Drop: Brave (no free tier), Jina search (key), Mojeek (paid), lite.duckduckgo.com (captcha). Marginalia only as optional tier 5b.
web_fetch: max_chars 8000 (4000 when num_ctx <= 8192); stdlib -> r.jina.ai -> sandbox Chromium; SSRF guard on.
SearXNG: Docker, publish 127.0.0.1:8888 only, json enabled, limiter false, ~300-500 MB RAM.
```

---

## B. Auto-compaction on a small context

### B.1 How others decide

| Tool | WHEN | Verbatim | Summary | UI | Source |
|---|---|---|---|---|---|
| **Codex** | tokens ≥ `model_auto_compact_token_limit`, **capped at 90 % of the window**; `effective_context_window_percent` default **95** | recent user messages (~20k tokens) + summary; initial context re-injected | handoff prompt (B.2) + `summary_prefix.md` | footer `N% context left`; protocol event `ContextCompacted` | *primary*: `refs/openai_codex/codex-rs/protocol/src/openai_models.rs:412,578-590`, `tui/src/bottom_pane/footer.rs:949-953`; prompt via [gist](https://gist.github.com/badlogic/cd2ef65b0697c4dbe2d13fbecb0a0a5f) (`core/` is not in our sparse clone) |
| **Claude Code** | sources conflict: ~95 % most cited; `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` lowers it; warning near 80 %; old tool outputs cleared first | CLAUDE.md re-read each cycle; `/compact <focus>` | whole history → LLM summary, restart from it | "context left until auto-compact" meter | *secondary* ([morphllm](https://www.morphllm.com/claude-code-auto-compact), [Vaughan](https://codex.danielvaughan.com/2026/04/14/context-compaction-deep-dive-codex-cli-claude-code-opencode/)); no official page found |
| **OpenCode** | v1: usage ≥ limit − `reserved` (min(20k, max output)); an issue reports a hardcoded 75 % in one build. **v2**: preflight near the limit; `compaction.{auto, keep.tokens, buffer}` | **recent 15,000 tokens** (`keep.tokens`) | summarises the **entire** conversation (reuses prompt cache); later compactions update the existing summary | `session.compaction.*` events | *primary* [opencode.ai/v2/docs/compaction](https://opencode.ai/v2/docs/compaction); [issue 11314](https://github.com/anomalyco/opencode/issues/11314), [learnopencode](https://learnopencode.com/en/5-advanced/20-compaction) (secondary) |
| **Cline** | "approaching the limit", number undocumented; non-Anthropic models fall back to rule-based truncation | task lists survive | "comprehensive summary", technical details and decisions | a **summarization tool call with its cost**; checkpoints restore | *primary* [docs.cline.bot/features/auto-compact](https://docs.cline.bot/features/auto-compact) |
| **Roo Code** | threshold slider, docs default 100 %, enabled by default (clamp 5–100 per a gist: secondary) | slash command in the first message | AI condense; custom prompt allowed | condense metrics with cost; checkpoints rewind | *primary* [docs.roocode.com](https://docs.roocode.com/features/intelligent-context-condensing) |
| **Open WebUI** | **off by default**; threshold default **80,000** tokens (`CONTEXT_COMPACTION_TOKEN_THRESHOLD`), per-model override; summariser defaults to the chat's own model; on failure sends full history | recent messages | summary replaces older block | none documented | *primary* [docs.openwebui.com/troubleshooting/context-window](https://docs.openwebui.com/troubleshooting/context-window) |

Patterns worth copying: (1) cheap tier first, clearing old tool outputs before spending an LLM call (Claude Code,
OpenCode v1 prune); (2) merge into the previous summary rather than re-summarise (OpenCode, Codex); (3) the
summariser is the chat's own model (Open WebUI, Cline, OpenCode); (4) fail open (Open WebUI); (5) show it as an
inspectable row (Cline) beside a context meter (Codex).

### B.2 WHAT the summary prompt says

Codex `core/templates/compact/prompt.md` (verbatim, from the gist):

> You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.
> Include: Current progress and key decisions made; Important context, constraints, or user preferences; What remains to be done (clear next steps); Any critical data, examples, or references needed to continue.
> Be concise, structured, and focused on helping the next LLM seamlessly continue the work.

Its `summary_prefix.md` frames the stored summary as work by "another language model" to build on. Claude Code's
(community-extracted, secondary) asks for what was accomplished, work in progress, files, next steps, user
constraints. Our `COMPACT_PROMPT` (pi-style Goal / Preferences / Done / In progress / Key facts / Next) already
matches; the version below only tightens it for a 4B model.

### B.3 VRAM: can `num_ctx` go to 8k / 16k? (*measured*)

Method: fresh load per row via `/api/generate` with `options.num_ctx`, then `/api/ps`. Second server on port 11500
with `OLLAMA_KV_CACHE_TYPE=q8_0` (its log shows `--cache-type-k q8_0 --cache-type-v q8_0 --flash-attn on`). Both
with flash attention. Desktop held 1.05 GiB. Figures in GiB; "CPU" = part of the model Ollama kept in RAM.

| Model | num_ctx | KV f16: total / CPU | KV q8_0: total / CPU | decode t/s (f16 / q8_0) |
|---|---|---|---|---|
| `qwen3.5:4b` (3.3 GB file) | 4,096 | 2.92 / 0 | 2.87 / 0 | 61 / 45 |
| | 16,384 | 3.39 / 0.21 | **3.13 / 0** | 53 / 60 |
| | 32,768 | 4.08 / 0.85 | 3.63 / 0.48 | 42 / 38 |
| `qwen3-abliterated:8b` Q4_K_M (5.0 GB) | 4,096 | 5.39 / **1.84** | 5.14 / 1.64 | 24.6 / 24.3 |
| | 8,192 | 5.96 / 2.44 | 5.44 / 1.86 | 21.7 / 24.8 |
| | 16,384 | 7.12 / 3.60 | 6.09 / 2.48 | 19.0 / 22.1 |

(One generation of 8 tokens per cell, so decode rates are rough.)

- **Qwen3.5-4B is nearly free to extend.** Only 8 of 32 layers are full attention (`full_attention_interval 4`, the
  rest SSM), 4 KV heads × 256 dim ≈ 32 KiB/token in f16. 16k fits entirely on the GPU with q8_0; 32k spills.
- **An 8B Q4 does not fit this card at any context.** 5 GB of weights plus the desktop's 1.05 GiB exceed 6 GiB;
  Ollama keeps 1.6–1.8 GiB in RAM even at 4k. More context only grows the CPU side. Qwen3-8B KV is 36 layers × 8 heads
  × 128 × 2 = 144 KiB/token (f16): the formula predicts +1.69 GiB from 4k→16k, measured +1.73; q8_0 (~76 KiB/token)
  predicts +0.92, measured +0.95. `q8_0` halves the growth (~3 t/s faster at 16k) but cannot make the 8B fully GPU-resident.
- `q8_0` KV is reported as a small quality loss, `q4_0` larger ([smcleod.net](https://smcleod.net/2024/12/bringing-k/v-context-quantisation-to-ollama/),
  [llmhardware.io](https://llmhardware.io/guides/kv-cache-quantization-ollama-llama-cpp), secondary). It is server-wide
  (also hits gpt-oss:20b). Set it in the drop-in: `Environment="OLLAMA_KV_CACHE_TYPE=q8_0"`, then `systemctl restart ollama`
  (not applied by me).

### B.4 Context budget (constraint from the repo)

20 tools + system prompt ≈ **2,500 tokens**: 61 % of a 4,096 window, 30 % of 8k, 15 % of 16k. So 4,096 cannot host the
full agent; the repo already runs 16k (4B) and 8k (8B). Ollama's final chunk `prompt_eval_count` is the whole prompt just
sent (system + tools + history + new message), so `used = prompt_eval_count + eval_count` is a floor for the next request.
It can under-report on a prompt-cache hit: fall back to `chars/3.5 + 2500` when it is missing or lower than the last estimate.

### B. Recommendation

```
Model/ctx:  qwen3.5:4b, num_ctx 16384, OLLAMA_KV_CACHE_TYPE=q8_0 (+ FLASH_ATTENTION=1, already on): 3.13 GiB, 0 spill, ~60 t/s.
            Don't use 32k (spills). 8B stays at 8192 (spill unavoidable). Don't ship 4096 with 20 tools.
Tier 1 (no LLM)  at used >= 55% of num_ctx: replace tool outputs older than the last 2 exchanges with
                 "[output cleared: <tool>, <N> chars]" (keep the call line).
Tier 2 (LLM)     at used >= 72% of num_ctx (11,800 of 16,384; 5,900 of 8,192), or when the fit check fails:
                 used + len(new_msg)/3.5 + 1,500 (tool-output reserve) + 400 (answer) >= num_ctx.
Keep verbatim:   last 2 exchanges, but only if they total <= 25% of num_ctx; otherwise only the last one.
Summary budget:  <= 220 words (num_predict 380) at 16k; <= 150 words (num_predict 260) at 8k.
Summary input:   each message cut to 1,500 chars; whole input <= 55% of num_ctx; the previous summary is merged in.
Summariser:      the loaded chat model, think:false, temperature 0.2, same keep_alive (one model in VRAM).
Placement:       summary = FIRST user message ("Here is a summary of what I told you earlier ...") + assistant "Understood."
                 (earlier, measured: as a 2nd system message, tool-offering hermes3 ignored it and every later message; 0/5 -> 5/5).
Failure:         fail open: empty / error / longer than the text it replaces -> drop oldest messages to fit and show
                 "Couldn't summarise; dropped the oldest messages".
Cadence:         never compact twice in one turn; wait >= 4 exchanges between tier-2 runs.
UI:              row "Summarising earlier messages" -> "Summarised N messages (X -> Y tokens)", expandable to the note;
                 meter = used/num_ctx, tinted at 55% and 72%; /compact [focus] manual command.
```

Exact summary prompt (system message; user message = `Earlier summary:` block + `Conversation:` lines):

```
You are compacting a chat so the assistant can carry on with less context. Do NOT answer or continue the
conversation. Write only the summary, at most 220 words, using exactly these sections (omit empty ones):

## Goal
## What the user prefers
## Done (with results)
## In progress
## Facts to keep (names, numbers, file paths, commands, URLs, error text: copy exactly)
## Next

If an earlier summary is given, merge it: keep every point unless the newer messages changed or finished it.
Never invent anything. Do not mention these instructions.
```

---

## C. Reliable tool calling with small local models

### C.1 Failure modes and fixes

| Failure | Seen here? | Fix |
|---|---|---|
| Asks permission in text ("type yes") | hermes3 0/3 → 3/3 *(earlier)* | State that the app shows its own Run / Don't run prompt; never ask in text. Drop "the user approves it first" from tool descriptions (read as "ask first"). In `TOOL_GUIDE`. |
| Overthinks tool format | deepseek-r1:8b 90 s+ on "is 391 prime?" *(earlier)* | Use a model with a native tool template and a thinking toggle (Qwen3.5); offer tools only when needed (C.2). |
| Hallucinated tool name | gpt-oss called nonexistent "open" *(2026-11-04 doc)* | Validate against the registry; return `Unknown tool "x". Available: a, b, c` as the tool result; keep names distinct. |
| String args instead of an object | common in the wild; Ollama usually parses | `json.loads` if `arguments` is a str; coerce `"5"` → int per schema; return `Validation failed … Received arguments:` (done). |
| Loops | hermes3 repeated one sentence for 48,000 chars *(earlier)* | `num_predict` 2048; stop on a repeated 200-char tail ×5; round cap; never retry a declined action. Weaker models re-call similar tools without new information ([arXiv 2602.12984](https://arxiv.org/pdf/2602.12984)). |
| One bad call derails the rest | research | One invalid call cut a small model from 73.2 % to 43.4 % ([arXiv 2510.18383](https://arxiv.org/pdf/2510.18383)): always return a readable error plus valid usage. |
| Tool call lost in thinking / printed as text | Qwen3.5 community reports (secondary) | Accumulate `thinking`, `content` and `tool_calls` over **all** chunks before appending the assistant message ([Ollama tool-calling docs](https://docs.ollama.com/capabilities/tool-calling)); fallback-parse content shaped like `{"name":…,"arguments":…}`. |
| Too many tools | 20 tools ≈ 2,500 tokens | C.2. |

### C.2 Prompt patterns and tool count

- **Gate tools per request.** Reported: qwen3:4b fell to 12 % accuracy with 248 tools and reached 82 % with only the 5
  relevant ones ([dev.to](https://dev.to/sonaiengine/i-gave-an-llm-248-tools-and-accuracy-dropped-to-12-heres-what-fixed-it-91h),
  secondary). Another test saw degradation between **25 and 50 tools**, worst with near-duplicates
  ([dev.to](https://dev.to/craigtracey/we-gave-llms-150-tools-heres-what-broke-2jaj), secondary). 20 tools is under that
  but costs 2,500 tokens. Chit-chat needs none: *measured* qwen3.5:4b answered "Is 391 a prime number?" and "capital of
  Australia?" without a tool, 2/2 each, in 6.6 s and 2.0 s.
- **Keyword router (no LLM)** picks groups: `files` (read/write/edit/ls/find/grep) on paths, `~/`, "file", "folder";
  `web` on "search", "latest", "news", "price", URLs; `machine` (run_command, launch_app, open_url) on "run", "open",
  "launch", "install", "start"; `desktop` (active_window, system_info, clipboard, selection) on "screen", "window",
  "clipboard", "selected", "my cpu/ram/battery"; `agent` (remember, update_plan, ask_user) is cheap, always on.
  No match → **no tools**. Keep the chosen set for the rest of the turn.
- **System-prompt rules that moved results** *(earlier, measured)*: (1) "When the user asks you to run, open or do
  something, call the tool in this reply"; (2) "the app shows the user a Run / Don't run prompt itself, so never ask for
  permission in text"; (3) "Otherwise answer directly with no tool"; (4) "after a tool returns, answer from its result;
  if it failed or was declined, say so in one line"; (5) today's date in the prompt.
- Tool descriptions: one sentence starting with a verb; flat parameters, ≤ 3, `enum`s where possible.
- `think` is a boolean for most models, a level for gpt-oss ([docs](https://docs.ollama.com/capabilities/thinking)).
  Use `think:false` for summaries and for turns the router classed as no-tool chit-chat. An earlier run found qwen3:4b with
  `think:false` "reasons inside the answer instead", so measure before promising a speed-up.
- Tool results: head + tail truncation to 4 KB, ANSI stripped (done); keep `tool_name` on role=tool messages.

### C.3 Which small model (sizes/badges from the ollama.com library pages, fetched today)

| Tag | Size | Badges | Verdict for 6 GiB |
|---|---|---|---|
| **`qwen3.5:4b`** (`4b-q4_K_M`) | 3.3 GB | vision, tools, thinking; 256K; `think` levels `false,true`, default true (`ollama show`) | **Pick.** *measured* tool habits **10/10** (run_command, launch_app, active_window, two no-tool prompts; 2 trials each), 2.0–6.6 s/turn at num_ctx 4096; 2.9–3.1 GiB at 4k–16k. Vision removes the vision hop. |
| `qwen3.5:2b` | 1.9 GB | same | Possible fast tier; untested. |
| `qwen3.5:4b-mtp-q4_K_M` | 4.1 GB | same + MTP | Untested; bigger. |
| `qwen3.5:9b` | 6.6 GB | same | Doesn't fit. |
| `qwen3:4b` | 2.5 GB (256K, 2507 build) | tools, thinking | Good, text-only. *earlier*: tools 3/3, but plain questions used a tool 1–2/3 times, 7–23 s/turn. |
| `qwen3-vl:4b` | 3.3 GB | vision, tools, thinking | Alternative if Qwen3.5 vision disappoints. |
| `qwen3:8b` (`8b-q4_K_M`) | 5.2 GB | tools, thinking | Spills 1.6–2.5 GiB to RAM (measured on the abliterated variant): 19–25 t/s. |
| `llama3.2:3b` | 2.0 GB | tools | Fits; 2024 model, no thinking; no 2026 benchmark found. |
| `granite4:micro` / `:3b` | 2.1 GB | tools | Tuned for tool calling / instruction following; no thinking; no benchmark found. |
| `gemma4:e2b` (`it-q4_K_M` 4.6 GB, `it-qat` 4.3 GB) | 4.3–4.6 GB | vision, tools, thinking | Fits tightly; `gemma4:e4b` (6.1–6.6 GB) doesn't. |
| `hermes3:8b` / `:3b` | 4.7 / 2.0 GB | tools | Superseded. |
| `deepseek-r1:8b` | ~5 GB | tools + thinking listed | Measured not to call tools *(earlier)*. Drop. |
| `gpt-oss:20b` | 13 GB MXFP4 | tools, thinking (levels) | Your "Deep": MoE through RAM, ~17 tok/s, 9/10 tools *(2026-11-04 doc)*. |

No independent 2026 benchmark compares these 2–4B models side by side (the BFCL snippets I found cover 7–9B models
and single community runs: [reddit snapshot](https://reddit.sentinel-team.org/posts/1sb84oy/snapshots/2026-04-03T21%3A20%3A24.375333Z),
secondary). The ranking rests on badges, file sizes and our own harness. **Harness bug:** the in-repo
`tests/agent/live/toolhabits.py` now crashes because its `Decline` stub lacks `take_steers()`, which `run_turn` calls
at `bin/rice_agent.py:1592`. I ran a patched copy from the scratchpad and did not edit the repo.

### C. Recommendation

```
Default model:  qwen3.5:4b, num_ctx 16384, KV q8_0; temperature 0.4 for tool turns, 0.2 for summaries. One 3.3 GB model gives
                vision + tools + thinking, so minicpm-v and the unload hop can go. Keep gpt-oss:20b as "Deep"; keep the abliterated pair as the uncensored picks.
Tool gating:    keyword router -> send 0, ~6 or at most 12 tools per request, never all 20 by default. Chit-chat: no tools, think:false.
Rounds:         6 per turn (plan); on the last round send no tools and ask for an answer. Allow 10 only after update_plan was called.
Guard rails:    validate name+args; str args -> json.loads; unknown name -> "Unknown tool X. Available: ..."; the same call with the same
                arguments twice -> "You already called this; answer from the result."; declined = no retry.
Prompt:         keep TOOL_GUIDE; add "Call at most one tool at a time unless the calls are independent." and today's date.
Do not use:     hermes3 or deepseek-r1 for tools. Fix the harness stub, then run toolhabits.py (5 trials) on any model before switching.
```

---

## D. Desktop-app feature checklist (ChatGPT and Claude, 2026)

Evidence: OpenAI [release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes) and
[releases.sh](https://releases.sh/release/rel_GKfuaFZioeFajr6Ui2nnb-chatgpt-desktop-app-unifies-chat-work-and-codex)
(July 2026: the desktop app unifies **Chat / Work / Codex**; Work = multi-step tasks over local files and desktop apps
"with your permission", a built-in browser, scheduled/triggered tasks; Voice on GPT-Live-1; Projects and unified Recents;
Plugin Directory replacing the App Directory; reviews conflict on whether Projects and Scheduled are in the redesigned
desktop app). Anthropic: Cowork generally available (dates conflict: 25 Mar vs 9 Apr 2026), skills + plugins + connectors
(25 Feb 2026), Claude Code desktop redesign with Routines (14 Apr 2026), monthly recap beta (9 Jul 2026)
([support.claude.com](https://support.claude.com/en/articles/12138966), [gradually.ai](https://www.gradually.ai/en/changelogs/claude-desktop/),
secondary). Several aggregator pages were low quality, so this list is inferred from release notes, not an inventory.

Plan column: **has** = in the plan or already in code; **gap** = not in the plan text; **no** = the plan excludes it.

| Feature | In apps | Value here | Plan |
|---|---|---|---|
| Streaming reply, Stop | both | **essential** | has |
| Markdown + code blocks with copy | both | **essential** | has? (not in plan tasks; verify) |
| Tool rows with live status, approvals | both (Work / Cowork permissions) | **essential** | has (Tasks 2–3, 7–8) |
| Reasoning display | both | **essential** | has |
| Copy / regenerate / edit-and-resend | both | **essential** | has (Task 6) |
| Model picker | both | **essential** | has (Task 9) |
| Context meter + compaction | Claude Code / Codex | **essential** | has (Task 12; compaction in code) |
| Image input (paste, drop, screenshot) | both | **essential** | has |
| Global hotkey quick entry | both | **essential** | has (Super+Ctrl+Shift+A) |
| History: list, **search**, rename, delete, auto-title | both | **essential** | **gap** (search and auto-title not in plan; check what the chat store has) |
| Web search with sources | both | **essential** | has |
| Memory across chats; custom instructions | both | **essential** | has in code (`remember` + 3 KB `memory.md`; `AGENTS.md`) |
| **File attachments** (PDF, text, code) | both | **essential** | **gap** (plan: images only) |
| Slash commands, skills | Claude | nice | has (Task 12; skills in code) |
| Follow-up / steer while running | Codex | nice | has in code (`take_steers`) |
| Export chat to Markdown | both | nice | **gap** (~20 lines) |
| Scheduled / recurring tasks | ChatGPT Work, Claude Routines | nice | **gap** |
| Projects (per-folder instructions + files) | both | nice | no (one global `AGENTS.md` is enough) |
| Voice in/out | ChatGPT | nice | no |
| Connectors / MCP / plugins | both | nice | no |
| Artifacts / canvas | both | nice | no |
| Computer use / browser agent | Work, Cowork | skip | not for a 4B model; `launch_app` / `open_url` + Chromium sandbox suffice |
| Branching conversations | ChatGPT | skip | no (YAGNI per plan) |
| Sharing, collaboration, org admin | both | skip | n/a |
| Thumbs up/down feedback | both | skip | nobody to send it to |
| Usage recap, cloud sync, accounts | Claude / both | skip | local-only is the point |

### D. Recommendation

```
Add before shipping:  1) history search + auto-title (first user message -> <=6 words, model call with think:false after turn 1)
                      2) file attach/drop for text, code and PDF (PDF via pdftotext -layout, first 6 KB, say it was cut); no new protocol: inject the path and let `read` do it
                      3) /export (Markdown) and /compact [focus]
Add after:            4) scheduled prompt = systemd --user timer running `rice-ollama agent` with a saved prompt, then a notification
                      5) side preview for fenced html / svg / mermaid blocks (artifact-lite)
                      6) push-to-talk voice (whisper.cpp in, piper out) only once text is solid
Keep skipped:         MCP, projects, branches, sharing, computer use, accounts, feedback buttons
Nothing in the plan needs removing.
```

---

## Not settled by public sources

- Claude Code's exact auto-compact trigger and prompt: no official page; figures above are secondary.
- Ollama `web_search` free-tier quota: unpublished. Mojeek trial size: unpublished. Marginalia shared-key limit: "often limited".
- Bing HTML selectors were not re-run; DDG lite blocked on its single request today (one sample).
- SearXNG RAM and install were not run here; 300–500 MB is from reports.
- qwen3.5:4b was tested with 2 trials per prompt and Ollama's default `think`; 10/10 is a small sample.
