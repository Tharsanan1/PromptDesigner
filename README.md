# PromptDesigner — Visual AI Workflow & Prompt Designer

Native macOS app for designing structured AI prompts and multi-agent workflows as a visual language.

**Core principle:** You write the instructions — the canvas expresses how they relate. JSON is the source of truth. An LLM compiler skill converts it semantically into a polished natural-language prompt.

## Features

- **15 block types:** Objective, Context/Input, Main Agent, Subagent, Task, Skill, Sequence, Parallel, Condition, Delegation, Handoff, Review, Retry, Completion, Final Output
- **7 typed connections:** Sequence, Delegate, Handoff, Parallel Branch, Review, Condition True/False, Correction — each with distinct visuals; execution order from graph, not position
- **Native canvas:** Pan, zoom (25–200%), grid, minimap, drag, selection, ports (output → input drag to connect)
- **Inspector:** Edit title, instructions (markdown), type-specific properties live
- **Validation:** Live diagnostics for disconnected blocks, missing fields, parallel/condition/review issues, cycles, dangling edges
- **JSON source of truth:** Export/import `*.pwd.json` lossless; auto-save; recent files
- **Undo/redo:** ≥100 steps
- **Duplicate / patterns:** Save selection as reusable pattern (`~/Library/Application Support/PromptDesigner/Patterns/`)
- **LLM compiler (OpenRouter only):** `POST https://openrouter.ai/api/v1/chat/completions` with dedicated skill; preserves every block/connection, explains delegation/handoffs, sequential/parallel, conditions, review gates; reports warnings; produces coverage map; adapts to Generic/Claude/OpenAI/Gemini
- **Preview & compare:** Execution order, prompt + warnings + coverage table (click highlights block)
- **Project browser:** Sidebar file list, search, templates (Single Task, Subagents, Pipeline)
- **Local-first:** No backend, no account. Files in `~/Documents/PromptDesigner/` and `~/.config/prompt-designer/`. API key reused from `~/.config/quickassist/config.json` or `~/.config/prompt-designer/config.json` or `OPENROUTER_API_KEY`
- **Future QuickAssist handoff:** Via shared JSON + `quickassist://open?file=` (see `docs/integration.md`)

## Build & Run

```bash
./build.sh                 # builds PromptDesigner.app
open PromptDesigner.app     # launch
```

Requires macOS 13+, Xcode Command Line Tools (`xcode-select --install`). No browser, no server.

## API Key

Set once:

```bash
# Option A: reuse QuickAssist
cat ~/.config/quickassist/config.json # ensure providers[openrouter].api_key set via QuickAssist ✨ → Set API Keys…

# Option B: local
mkdir -p ~/.config/prompt-designer
echo '{"openrouter_key":"sk-or-v1-..."}' > ~/.config/prompt-designer/config.json

# Option C: env
export OPENROUTER_API_KEY=sk-or-v1-...
```

Get a free key at https://openrouter.ai/keys (model `google/gemma-4-31b-it:free` used for compilation).

## Usage

1. **Palette (left):** Double-click or drag a block type onto canvas. Templates via buttons or File → New from Template.
2. **Canvas (center):** Drag blocks, drag from right port (●) to left port (○) to connect. Select to inspect. Pan by dragging background, zoom with toolbar.
3. **Inspector (right):** Edit instructions/properties, see connections, duplicate/delete.
4. **Diagnostics (left bottom):** Warnings → click to jump.
5. **Compiler (right bottom):** Choose target env, click Compile → see prompt, warnings, coverage map (click row highlights block + excerpt). Copy prompt.
6. **File:** New/Open/Save/Export JSON… (⌘S/⌘O/⌘E). Auto-save to current file.

## JSON Schema

```json
{
  "version": "1.0",
  "metadata": {"name":"...","objective":"...","createdAt":"...","updatedAt":"...","description":"..."},
  "blocks": [{"id":"...","type":"task","title":"...","instructions":"...","properties":{"...":"..."},"position":{"x":0,"y":0},"size":{"width":240,"height":110}}],
  "connections": [{"id":"...","from":"...","to":"...","semantics":"delegate","label":"","condition":""}]
}
```

## Integration with QuickAssist

Standalone — no runtime coupling. Share via file:

```bash
# Export from PromptDesigner then:
open "quickassist://open?file=/path/to/workflow.pwd.json" # future
# or
cp ~/Documents/PromptDesigner/*.pwd.json ~/.config/prompt-designer/workflows/
```

See `docs/integration.md` for contract.

## Examples

`Examples/*.pwd.json` — Single Task, Subagents, Pipeline, Complex (10+ blocks, parallel, condition, review, retry).

