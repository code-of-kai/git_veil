# Encrypted Add Workflow – Tuning Knobs

This note lists every runtime option the new `GitFoil.Workflows.EncryptedAdd`
pipeline understands, along with suggested ways we could expose them. Nothing
here is wired into the CLI yet; the table is meant to help decide what belongs
in the default UX, what should live in advanced docs, and what should stay
internal.

| Option | What it does | Current default | Potential surfaces | Notes |
| --- | --- | --- | --- | --- |
| `:max_concurrency` | Caps how many concurrent `git add` tasks we spawn. | `System.schedulers_online() |> max(1)` | *CLI flag*: `git-foil encrypt --concurrency 4`<br>*Init prompt*: reuse `Helpers.Concurrency` instructions/prompt (optional)<br>*Config*: persisted value in `.git/git_foil/config.toml` | Core performance knob; should be easy to override. We already have helper module for messaging/prompting. |
| `:batch_size` | Number of file paths bundled into a single `git add -- <files...>` invocation. | `1` | *Advanced config only* (e.g., `git-foil config set workflow.batch_size 8`), documented in `ADVANCED.md`. | Increasing reduces process spawn overhead but gives coarser error reporting. Probably hide behind advanced docs. |
| `:timeout` | Kills a worker task if `git add` exceeds the limit. | `:infinity` | *Advanced config* (e.g., environment variable `GIT_FOIL_ADD_TIMEOUT_MS`). | Useful for automation that wants deterministic failure, but most users shouldn’t touch it. |
| `:progress_adapter` | Chooses how (or if) progress renders. | `ProgressBar` (built-in implementation) | *CLI flag*: `--no-progress` to swap in `Progress.Noop`<br>*Advanced config*: allow custom module for power users / tests. | Worth exposing at least the on/off toggle for CI. Module injection stays advanced. |
| `:progress_opts` | Label/width passed to the adapter. | Label set per command; width default `30`. | *Internal*, set by commands. | Keep internal – it’s presentation only. |
| `:telemetry_prefix` | Namespace for emitted telemetry events. | `[:git_foil, :encrypted_add]` | *Advanced docs only*. | Only instrumentation integrations need this. |
| `:index_lock_retries` | Number of times to retry when Git reports `index.lock` contention. | `25` (or `:infinity`) | *Advanced config* (e.g., `git-foil config set workflow.index_lock_retries 40`). | Helps when multiple Git processes contend; regular users rarely tweak it. |
| `:retry_backoff_ms` | Base backoff (ms) between retries; grows exponentially per attempt. | `50` | *Advanced config* / env var. | Useful on very slow disks; expose only in advanced docs. |

### Example CLI Flags (not implemented yet)

```
# run encrypt with explicit concurrency and without progress output
git-foil encrypt --concurrency 6 --no-progress

# re-encrypt using the recommended value detected at init time
git-foil re-encrypt --auto-concurrency
```

If we decide to surface these, the commands can:

1. Parse the flag(s) into keyword options for `EncryptedAdd.add_files/2`.
2. Report the chosen value using `GitFoil.Helpers.Concurrency.summary/1`.
3. Persist an override in repo config when invoked via `git-foil config`.

Advanced settings (batch size, timeout, telemetry prefix) should live in
`ADVANCED.md` or another expert-facing doc, possibly toggled via environment
variables to avoid cluttering the mainstream UX.
