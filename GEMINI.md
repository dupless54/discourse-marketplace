@AGENTS.md

# Gemini adapter

Treat `AGENTS.md` as canonical. Do not recursively preload every local instruction file. Identify the directories involved in the current task, then read only their nearest `AGENTS.md`, the current state when relevant, and the minimum source/tests needed. Cross-model procedures are in `.agents/skills/`.
