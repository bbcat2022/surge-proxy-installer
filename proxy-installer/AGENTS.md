# Local development rules

- Read and follow repository-root `AGENTS.md` and `README.md` first. This file adds rules for `proxy-installer/`.
- Internal baselines are stored in the ignored `no-upload/` directory. Preserve frozen decisions; update affected records when an authorized iteration changes requirements or interfaces. Historical implementation-status statements are not evidence of current status.
- Only `tools/config_tool.py` may parse or write the YAML main configuration.
- Interface code must not modify configuration or invoke system commands.
- Protocol adapters must not write files or call systemd.
- High-impact operations must use the transaction and orchestration layers.
- Tests must use temporary paths and must not write `/etc`, `/usr/local/bin`, or `/etc/systemd/system`.
- Real VPS operations require explicit task-level authorization.
- From `proxy-installer/`, check the intended staged files before committing or publishing: `python3 tools/publication_guard.py --root .. --mode staged`. Check tracked files with `--mode tracked` before release; inspect new untracked files separately.
- Never publish root-level numbered requirement documents, live configuration, certificates, tokens, VPS addresses, or real test domains. Keep project-specific values only in the ignored `.private-upload-denylist` file.
- Documentation updates are part of each iteration: synchronize affected READMEs, install instructions, manifest notes, and test-coverage status with actual behavior. Follow the update mapping in repository-root `AGENTS.md`.
- Record local tests separately from real VPS and Surge verification. Do not expand a successful connection report into claims about untested update, rollback, uninstall, restart, or renewal scenarios.
