# Connection Actions

## Gemini conversation & text generation

**`send_messages` — Vertex: Send messages to Gemini models**

* Sends either a single message or a whole chat transcript (plus optional system instructions and tools) to a Gemini model via Vertex AI.
* Validates the model (if enabled), applies safety settings, and calls `generateContent`.
* Returns the raw Vertex response (candidates, safety ratings, token usage) and rate‑limit info.

**`translate_text` — Vertex: Translate text**

* Prompts Gemini to translate the provided text into a target language (source language optional).
* Forces a JSON-only reply and extracts just the translated string as `answer`, plus safety/usage.

**`summarize_text` — Vertex: Summarize text**

* Asks Gemini to produce a shorter version of the input text, obeying an optional max word count.
* Returns the summary as `answer`, plus safety/usage.

**`parse_text` — Vertex: Extract structured fields from text**

* Given a JSON schema, asks Gemini to pull those fields from freeform text.
* Returns a flat object with your schema’s keys (missing data becomes `null`) plus safety/usage.

**`draft_email` — Vertex: Generate an email**

* Turns a short description into an email draft with a subject and body (includes salutation/closing).
* Returns `subject` and `body`, plus safety/usage.

**`ai_classify` — Vertex: Classify text**

* Classifies text into one of your provided categories; can return confidence and alternatives.
* Low temperature by default to keep classifications steady.
* Returns `selected_category`, `confidence`, optional `alternatives`, plus safety/usage.

**`analyze_text` — Vertex: Answer questions about a passage**

* Answers a user question using only the supplied text (no outside knowledge).
* If the answer isn’t in the text, the `answer` comes back empty; also returns safety/usage.

**`analyze_image` — Vertex: Answer questions about an image**

* Sends your question and image bytes to a multimodal Gemini model.
* Returns a free‑text `answer` about the image, plus safety/usage.

---

## Embeddings & Vector Search

**`generate_embeddings` — Vertex: Batch text embeddings**

* Generates embeddings for many texts in batches (25 per API call) with rate‑limit/backoff handling.
* Returns one vector per input (with id/dimensions), a quick‑access `first_embedding`, a JSON blob of all embeddings, and batch metrics (processed counts, tokens, estimated cost savings, pass/fail/action).

**`generate_embedding_single` — Vertex: Single text embedding**

* Generates one embedding for one text (optional `title` prefix and `task_type`).
* Enforces a rough max length; returns vector, dimensions, model used, token estimate.

**`find_neighbors` — Vertex Vector Search: k‑NN query**

* Queries a **deployed** Vertex Vector Search index endpoint (you provide the endpoint host, endpoint id, deployedIndexId, and one or more query vectors/ids).
* Supports dense and sparse embeddings plus metadata/numeric filters; retries on transient errors.
* Returns a flattened `top_matches` list with distance and a normalized similarity score, plus the original `nearestNeighbors` block for compatibility, and pass/fail/action hints.

**`upsert_index_datapoints` — Vertex Vector Search: Upsert datapoints**

* Creates/updates vector datapoints in a Vertex index (validates the index and that it’s deployed).
* Processes in batches of up to 100 with simple retries; accepts restricts/crowding.
* Returns counts of successes/failures, per‑datapoint error details, and index stats (dimensions, totals, timestamps).

---

## Setup & legacy

**`test_connection` — Setup: Connectivity and permissions check**

* Runs health checks for Vertex AI and Google Drive; optionally verifies model access and a specific Vector Search index.
* Produces environment info, tests performed, errors/warnings, a summary, overall status, and (when verbose) quota notes and actionable recommendations.

**`get_prediction` (legacy)**

* Deprecated compatibility call to PaLM2 **text-bison** `:predict`.
* Returns raw predictions and token metadata; kept for older recipes.

---

## Google Drive helpers

**`fetch_drive_file` — Drive: Download one file**

* Accepts a Drive file **ID or URL**, fetches metadata, and (if requested) content.
* Google Docs/Sheets/Slides are exported to text; other files are downloaded.
* Returns metadata, extracted text (when applicable), and flags like `needs_processing` for non‑text (e.g., PDFs/images).

**`list_drive_files` — Drive: List files**

* Lists files with flexible filters (folder, modified dates, MIME type, exclude folders), ordered by most recently modified.
* Returns a compact file list (id/name/mime/size/mtime/checksum) plus pagination token and the exact query used.

**`batch_fetch_drive_files` — Drive: Download many files**

* Iterates over multiple IDs/URLs, reusing the single‑file logic.
* Can skip over failures or fail fast.
* Returns arrays of successful and failed items with metrics (totals, success rate, processing time).

**`monitor_drive_changes` — Drive: Track changes since last checkpoint**

* First run returns a **start token** (no changes).
* Subsequent runs take the saved token and return changes since then, grouped into added/modified/removed (simple heuristic) with a new token for the next run.
* Supports optional folder scoping and shared drives; returns a summary and whether more pages exist.

---

## Cross‑cutting behavior (applies to most Vertex actions)

* Optional **model validation** before calls; **rate limiting** with backoff and basic circuit‑breaker logic on retries.
* Consistent **safety ratings** and **usage** (token counts) surfaced in outputs.
* Clear error messages; extra upstream details when `verbose_errors` is enabled in the connection.
