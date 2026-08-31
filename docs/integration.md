# QuickAssist Integration Contract

PromptDesigner is standalone. QuickAssist integrates via **file handoff**, not shared process.

## Shared Artifacts

- **Workflow JSON:** `*.pwd.json` per FR-5 (versioned, Codable). Consumer reads `blocks`, `connections`, `metadata`.
- **Compiled prompt:** Markdown `.md` from compiler result `prompt` field.
- **Coverage map:** For verification, not required for execution.

## Paths

- PromptDesigner default: `~/Documents/PromptDesigner/` and `~/.config/prompt-designer/workflows/`
- QuickAssist config: `~/.config/quickassist/config.json` (reused for OpenRouter key)
- PromptDesigner key fallback: `~/.config/prompt-designer/config.json` `{"openrouter_key":"sk-or-..."}`
- Patterns: `~/Library/Application Support/PromptDesigner/Patterns/*.pwd.json`

## Handoff Mechanisms (future, no coupling now)

1. **File:** User exports JSON from PromptDesigner, opens in QuickAssist via File → Import or drag-drop.
2. **URL scheme (planned):** `quickassist://open?file=/absolute/path/to/workflow.pwd.json`
3. **Shared dir watch:** QuickAssist can watch `~/.config/prompt-designer/workflows/` for new files.

## No Runtime Dependency

- No XPC, no shared library, no browser embedding.
- PromptDesigner does not import QuickAssist code; QuickAssist does not import PromptDesigner.
- Contract is JSON schema + file location + URL scheme docs.

## Versioning

- `version: "1.0"` — breaking changes bump minor/major, importer migrates.

## Security

- Workflows are local files; API key never embedded in JSON; compiler reads key from config at compile time only.

