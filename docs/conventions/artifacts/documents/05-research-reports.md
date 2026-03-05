# Research Reports

```
v<X>/research/{NN}-{source}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `{NN}` | Two-digit sequential number, starting at `01`. |
| `{source}` | Reference codebase analyzed (e.g., `tmux`, `zellij`, `ghostty`). |
| `{topic}` | What was researched (e.g., `resize-health`, `dirty-tracking`). |

## Required Content

- Specific source file paths and function/struct names from the reference codebase
- Factual findings only — no design recommendations
- Trade-offs observed (what works well, what doesn't)
- Known bugs or limitations in the reference implementation
