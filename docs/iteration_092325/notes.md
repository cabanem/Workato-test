# Notes on sequencing

* **PR 1** is pure fixes; land first.
* **PR 2** introduces shared runner/URL; touches 5 actions but is straightforward.
* **PR 3** simplifies discovery; safe after PR 1.
* **PR 4–5** are local changes (Drive / Vector); independent of each other.
* **PR 6–7** are internal plumbing; low blast radius.
* **PR 8–10** are cleanups; last by design.

---

# Quick regression checklist (run once after all PRs)

* **Auth**: `test` block at connector root returns both Vertex + Drive checks OK.
* **Generative**: `send_messages`, `translate_text`, `summarize_text`, `parse_text`, `draft_email`, `analyze_text`, `analyze_image` — produce answers; safety/usage present.
* **Embeddings**: Single + batch return vectors; batch metrics coherent.
* **Vector Search**: `find_neighbors` returns sorted `top_matches`; `upsert_index_datapoints` succeeds on valid vectors.
* **Drive**: Single + batch fetch; monitor changes returns added/modified/removed; initial token path works.

