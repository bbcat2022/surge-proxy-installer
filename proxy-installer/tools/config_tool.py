#!/usr/bin/env python3
"""Controlled YAML read/write helper for proxy-installer's main configuration."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable

import yaml


EXPECTED_SCHEMA_VERSION = 1
ALLOWED_TOP_LEVEL_KEYS = {"schema_version", "config_revision", "desired", "applied", "observed", "history"}
SENSITIVE_KEY_FRAGMENTS = ("password", "psk", "secret", "private", "token", "key")
OPERATION_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
FAILED_STAGE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
OPERATION_TYPES = {"deploy", "config-apply", "update", "uninstall", "certificate", "revision-restore"}
OPERATION_STATUSES = {"pending", "success", "partial-success", "failed", "rollback-success", "dirty", "interrupted"}


class ToolError(Exception):
    def __init__(self, category: str, summary: str) -> None:
        super().__init__(summary)
        self.category = category
        self.summary = summary


def is_sensitive_key(key: str) -> bool:
    return any(fragment in key.lower() for fragment in SENSITIVE_KEY_FRAGMENTS)


def redact(value: Any, inherited_sensitive: bool = False) -> Any:
    if inherited_sensitive:
        return "***REDACTED***"
    if isinstance(value, dict):
        return {key: redact(item, is_sensitive_key(str(key))) for key, item in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def emit(result: str, category: str, summary: str, **extra: Any) -> None:
    payload = {"result": result, "category": category, "summary": summary}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def validate_schema(data: Dict[str, Any], expected_schema: int) -> None:
    if set(data) - ALLOWED_TOP_LEVEL_KEYS:
        raise ToolError("validation", "configuration contains unsupported top-level fields")
    if data.get("schema_version") != expected_schema:
        raise ToolError("validation", "configuration schema_version is incompatible")
    if not isinstance(data.get("config_revision"), int) or isinstance(data["config_revision"], bool):
        raise ToolError("validation", "config_revision must be an integer")
    for key in ("desired", "applied", "observed", "history"):
        if key not in data or not isinstance(data[key], dict):
            raise ToolError("validation", f"{key} must be a mapping")


def load_yaml(path: Path, expected_schema: int) -> Dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except FileNotFoundError as exc:
        raise ToolError("dependency", "configuration file does not exist") from exc
    except (OSError, yaml.YAMLError) as exc:
        raise ToolError("validation", "configuration YAML cannot be read or parsed") from exc
    if not isinstance(data, dict):
        raise ToolError("validation", "configuration root must be a mapping")
    validate_schema(data, expected_schema)
    return data


def parse_patch(raw_patch: str) -> Dict[str, Any]:
    try:
        patch = json.loads(raw_patch)
    except json.JSONDecodeError as exc:
        raise ToolError("validation", "patch must be valid JSON") from exc
    if not isinstance(patch, dict):
        raise ToolError("validation", "patch root must be a mapping")
    if "schema_version" in patch or set(patch) - ALLOWED_TOP_LEVEL_KEYS:
        raise ToolError("validation", "patch contains unsupported fields")
    if "config_revision" in patch and (not isinstance(patch["config_revision"], int) or isinstance(patch["config_revision"], bool)):
        raise ToolError("validation", "config_revision patch value must be an integer")
    for key in ("desired", "applied", "observed", "history"):
        if key in patch and not isinstance(patch[key], dict):
            raise ToolError("validation", f"{key} patch value must be a mapping")
    return patch


def merge_mapping(current: Dict[str, Any], patch: Dict[str, Any]) -> Dict[str, Any]:
    merged = dict(current)
    for key, value in patch.items():
        merged[key] = merge_mapping(merged[key], value) if isinstance(value, dict) and isinstance(merged.get(key), dict) else value
    return merged


def collect_paths(value: Dict[str, Any], prefix: str = "") -> Iterable[str]:
    for key, item in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict):
            yield from collect_paths(item, path)
        else:
            yield path


def query_path(data: Dict[str, Any], path: str) -> Any:
    if not path or any(not segment for segment in path.split(".")):
        raise ToolError("validation", "query path must be dot-separated")
    value: Any = data
    for segment in path.split("."):
        if not isinstance(value, dict) or segment not in value:
            raise ToolError("validation", "query path is not allowed or does not exist")
        value = value[segment]
    return redact(value, any(is_sensitive_key(part) for part in path.split(".")))


def deployment_plan(data: Dict[str, Any]) -> Dict[str, Any]:
    """Return the non-sensitive portion of enabled protocol configuration.

    This is deliberately a separate, redacted view: shell orchestration may use
    it for preflight planning without ever receiving credentials from YAML.
    """
    protocols = data["desired"].get("protocols", {})
    if not isinstance(protocols, dict):
        raise ToolError("validation", "desired.protocols must be a mapping")
    planned = []
    for name in ("snell", "anytls", "hysteria2"):
        item = protocols.get(name)
        if item is None:
            continue
        if not isinstance(item, dict) or item.get("enabled") is not True:
            continue
        port = item.get("port")
        if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
            raise ToolError("validation", f"enabled {name} requires a valid port")
        entry: Dict[str, Any] = {"name": name, "port": port}
        if name == "snell":
            address = item.get("client_address")
            if not isinstance(address, str) or not address:
                raise ToolError("validation", "enabled snell requires client_address")
            entry["client_address"] = address
        else:
            domain = item.get("domain")
            if not isinstance(domain, str) or not domain:
                raise ToolError("validation", f"enabled {name} requires domain")
            entry["domain"] = domain
        if name == "hysteria2":
            port_range = item.get("port_hopping_range", "")
            if not isinstance(port_range, str):
                raise ToolError("validation", "hysteria2 port_hopping_range must be a string")
            entry["port_hopping_range"] = port_range
        planned.append(entry)
    if not planned:
        raise ToolError("validation", "no enabled protocols are configured")
    return {"protocols": planned, "confirmation_required": True}


def deployment_env(data: Dict[str, Any]) -> str:
    """Emit validated deployment inputs as shell assignments for the orchestrator.

    This is intentionally not a general YAML export. It is a narrow privileged
    interface used only after root-only configuration permissions are checked.
    Values are shell-quoted so protocol secrets never become executable input.
    """
    plan = deployment_plan(data)
    protocols = data["desired"]["protocols"]
    lines = [f"DEPLOY_SELECTED_PROTOCOLS={shlex.quote(','.join(item['name'] for item in plan['protocols']))}"]
    fields = {
        "snell": ("port", "psk", "client_address_type", "client_address", "mode"),
        "anytls": ("port", "password", "domain", "tfo", "reuse"),
        "hysteria2": ("port", "password", "domain", "port_hopping_range", "hop_interval", "gecko", "gecko_password", "download_bandwidth"),
    }
    for name, names in fields.items():
        item = protocols.get(name)
        if not isinstance(item, dict) or item.get("enabled") is not True:
            continue
        for field in names:
            if field not in item:
                raise ToolError("validation", f"enabled {name} requires {field}")
            value = item[field]
            if isinstance(value, bool):
                encoded = "true" if value else "false"
            elif isinstance(value, (str, int)) and not isinstance(value, bool):
                encoded = str(value)
            else:
                raise ToolError("validation", f"enabled {name} has invalid {field}")
            lines.append(f"{name.upper()}_{field.upper()}={shlex.quote(encoded)}")
    return "\n".join(lines) + "\n"


def deployment_domains(data: Dict[str, Any]) -> list[str]:
    """Return distinct TLS domains without exposing any protocol credentials."""
    domains: list[str] = []
    for item in deployment_plan(data)["protocols"]:
        if item["name"] in ("anytls", "hysteria2") and item["domain"] not in domains:
            domains.append(item["domain"])
    return domains


def deployment_applied_record(data: Dict[str, Any], operation_id: str) -> Dict[str, Any]:
    if not OPERATION_ID_PATTERN.fullmatch(operation_id):
        raise ToolError("validation", "operation_id is invalid")
    protocols: Dict[str, Dict[str, Any]] = {}
    for item in deployment_plan(data)["protocols"]:
        protocol = dict(item)
        name = protocol.pop("name")
        protocols[name] = protocol
    return {
        "operation_id": operation_id,
        "config_revision": data["config_revision"],
        "protocols": protocols,
    }


def atomic_write(path: Path, data: Dict[str, Any], expected_schema: int) -> None:
    validate_schema(data, expected_schema)
    serialized = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
    temporary_name = ""
    try:
        fd, temporary_name = tempfile.mkstemp(prefix=".config.yaml.", dir=str(path.parent))
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(serialized)
            handle.flush()
            os.fsync(handle.fileno())
        with Path(temporary_name).open("r", encoding="utf-8") as handle:
            candidate = yaml.safe_load(handle)
        if not isinstance(candidate, dict):
            raise ToolError("validation", "temporary YAML root must be a mapping")
        validate_schema(candidate, expected_schema)
        os.replace(temporary_name, path)
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    except ToolError:
        raise
    except (OSError, yaml.YAMLError) as exc:
        raise ToolError("external", "atomic configuration write failed") from exc
    finally:
        if temporary_name and os.path.exists(temporary_name):
            os.unlink(temporary_name)


def initial_config(expected_schema: int) -> Dict[str, Any]:
    return {
        "schema_version": expected_schema,
        "config_revision": 0,
        "desired": {},
        "applied": {},
        "observed": {},
        "history": {},
    }


def operation_record(
    operation_id: str,
    operation_type: str,
    status: str,
    summary: str,
    failed_stage: str = "",
    repair_advice: str = "",
) -> Dict[str, str]:
    if not OPERATION_ID_PATTERN.fullmatch(operation_id):
        raise ToolError("validation", "operation_id is invalid")
    if operation_type not in OPERATION_TYPES:
        raise ToolError("validation", "operation type is unsupported")
    if status not in OPERATION_STATUSES:
        raise ToolError("validation", "operation status is unsupported")
    if not summary or len(summary) > 240 or "\n" in summary or "\r" in summary:
        raise ToolError("validation", "operation summary is invalid")
    if failed_stage and not FAILED_STAGE_PATTERN.fullmatch(failed_stage):
        raise ToolError("validation", "failed stage is invalid")
    if repair_advice and (len(repair_advice) > 240 or "\n" in repair_advice or "\r" in repair_advice):
        raise ToolError("validation", "repair advice is invalid")
    record = {"id": operation_id, "type": operation_type, "status": status, "summary": summary}
    if failed_stage:
        record["failed_stage"] = failed_stage
    if repair_advice:
        record["repair_advice"] = repair_advice
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--schema-version", type=int, default=EXPECTED_SCHEMA_VERSION)
    parser.add_argument("--dry-run", action="store_true")
    subparsers = parser.add_subparsers(dest="operation", required=True)
    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("--force", action="store_true")
    subparsers.add_parser("read")
    subparsers.add_parser("validate")
    subparsers.add_parser("deployment-plan")
    subparsers.add_parser("deployment-env")
    subparsers.add_parser("deployment-domains")
    commit_deployment_parser = subparsers.add_parser("commit-deployment")
    commit_deployment_parser.add_argument("--operation-id", required=True)
    query_parser = subparsers.add_parser("query")
    query_parser.add_argument("--path", required=True)
    patch_parser = subparsers.add_parser("patch")
    patch_parser.add_argument("--patch", required=True)
    restore_parser = subparsers.add_parser("restore")
    restore_parser.add_argument("--from", dest="source", required=True, type=Path)
    operation_parser = subparsers.add_parser("record-operation")
    operation_parser.add_argument("--operation-id", required=True)
    operation_parser.add_argument("--operation-type", required=True)
    operation_parser.add_argument("--status", required=True)
    operation_parser.add_argument("--summary", required=True)
    operation_parser.add_argument("--failed-stage", default="")
    operation_parser.add_argument("--repair-advice", default="")
    args = parser.parse_args()
    try:
        if args.operation == "init":
            if args.config.exists() and not args.force:
                raise ToolError("conflict", "configuration file already exists")
            try:
                args.config.parent.mkdir(mode=stat.S_IRWXU, parents=True, exist_ok=True)
            except OSError as exc:
                raise ToolError("external", "configuration directory cannot be created") from exc
            atomic_write(args.config, initial_config(args.schema_version), args.schema_version)
            emit("success", "none", "configuration initialized", changed=True)
            return 0
        if args.operation == "restore":
            candidate = load_yaml(args.source, args.schema_version)
            if args.dry_run:
                emit("success", "none", "dry-run restore validated", changed=False, dry_run=True)
            else:
                atomic_write(args.config, candidate, args.schema_version)
                emit("success", "none", "configuration restored atomically", changed=True)
            return 0
        config = load_yaml(args.config, args.schema_version)
        if args.operation == "validate":
            emit("success", "none", "configuration is valid", changed=False)
        elif args.operation == "deployment-plan":
            emit("success", "none", "redacted deployment plan read", changed=False, data=deployment_plan(config))
        elif args.operation == "deployment-env":
            # No JSON envelope: this command is consumed by a root-only shell
            # material builder and must never be used for human-facing output.
            sys.stdout.write(deployment_env(config))
        elif args.operation == "deployment-domains":
            sys.stdout.write("\n".join(deployment_domains(config)) + "\n")
        elif args.operation == "commit-deployment":
            updated = dict(config)
            updated["applied"] = deployment_applied_record(config, args.operation_id)
            if args.dry_run:
                emit("success", "none", "deployment commit validated", changed=False, dry_run=True)
            else:
                atomic_write(args.config, updated, args.schema_version)
                emit("success", "none", "deployment state committed", changed=True)
        elif args.operation == "read":
            emit("success", "none", "configuration read", changed=False, data=redact(config))
        elif args.operation == "query":
            emit("success", "none", "configuration value read", changed=False, value=query_path(config, args.path))
        elif args.operation == "record-operation":
            record = operation_record(
                args.operation_id,
                args.operation_type,
                args.status,
                args.summary,
                args.failed_stage,
                args.repair_advice,
            )
            updated = merge_mapping(config, {"history": {"last_operation": record}})
            if args.dry_run:
                emit("success", "none", "dry-run operation record validated", changed=False, dry_run=True)
            else:
                atomic_write(args.config, updated, args.schema_version)
                emit("success", "none", "operation summary recorded", changed=True)
        else:
            patch = parse_patch(args.patch)
            updated = merge_mapping(config, patch)
            validate_schema(updated, args.schema_version)
            paths = list(collect_paths(patch))
            if args.dry_run:
                emit("success", "none", "dry-run patch validated", changed=False, dry_run=True, modified_paths=paths)
            else:
                atomic_write(args.config, updated, args.schema_version)
                emit("success", "none", "configuration patched atomically", changed=True, modified_paths=paths)
        return 0
    except ToolError as exc:
        emit("failed", exc.category, exc.summary, changed=False)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
