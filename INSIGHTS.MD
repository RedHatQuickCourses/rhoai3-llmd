# Insights: rhoai3-llmd

## Course design

- **Standalone but aligned:** rhoai3-llmd is a standalone course; tone and structure mirror other rhoai3-* modules (Problem/Solution lead, prerequisites, clear lab steps, Day 2 ops, troubleshooting). Content was merged from llmops-llmd (AI-generated) and rhoai3-llmd chapter1 sample; all `[cite: ...]` and `[cite_start]` were removed for consistency and to avoid dependency on an external reference doc.
- **README Quick Start:** The README allows deploying the llm-d feature without reading the course: clone `rhoai3-llmd-deploy`, run setup script, apply `LLMInferenceService`, test with curl. This matches the rhoai3-deploy and rhoai3-maas pattern.
- **No appendix module:** Other rhoai3-* courses do not use a separate appendix; well-lit paths, KV cache deep dive, and glossary from llmops-llmd were not carried over as separate pages. Troubleshooting and summary are in chapter1; optional simulator is an outline (no Arcade iframes in repo).

## Structure

- **ROOT:** Single nav entry; index includes chapter1 index so the component home is the course intro (same pattern as rhoai3-storage, rhoai3-maas).
- **chapter1:** index (intro + value), section1 (architecture), section2 (lab), section3 (observability), section4 (troubleshooting), section5 (simulator optional), section6 (summary). Lab references `rhoai3-llmd-deploy` and a generic `llmd-deployment.yaml`; README and section2 stay in sync.

## Reuse

- Existing CSS and UI (ui-bundle, supplemental-ui) are unchanged. No new assets beyond content.
- If rhoai3-journey (or journey2) later includes rhoai3-llmd, the component name is `rhoai3-llmd`; shell pages and playbook would follow the same pattern as llmops-llmd (phase 4a).
