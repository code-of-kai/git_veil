# GitFoil Concurrency Build Log

## Entry 001 – Detect, Decide, Communicate

- **Context:** Upcoming work introduces parallel `git add` execution so clean filters encrypt files across multiple CPU cores. We need a shared record—lightweight ADR style—to explain the moving parts as we touch `init` and `encrypt`.
- **Decision:** Maintain this running log with concise checkpoints whenever we cross a meaningful milestone. Keeps stakeholders aligned without flooding the CLI stream.
- **Next focus:** Add a concurrency helper (CPU detection, prompts, CLI flag plumbing) that both commands can reuse, then refactor the commands to stream `git add` tasks concurrently while keeping progress output friendly.

