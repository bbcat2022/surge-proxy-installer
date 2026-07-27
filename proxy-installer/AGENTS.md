# Local development rules

- Treat repository-root baseline documents as read-only references.
- Only `tools/config_tool.py` may parse or write the YAML main configuration.
- Interface code must not modify configuration or invoke system commands.
- Protocol adapters must not write files or call systemd.
- High-impact operations must later use the transaction layer.
- Tests must use temporary paths and must not write `/etc`, `/usr/local/bin`, or `/etc/systemd/system`.
- Real VPS operations require explicit task-level authorization.
