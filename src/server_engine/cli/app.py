from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from server_engine.bootstrap import build_container

RUNTIME_KINDS: tuple[str, ...] = (
    "php",
    "apache",
    "nginx",
    "database",
    "redis",
    "memcached",
    "mailpit",
    "node",
    "phpmyadmin",
)

SITE_TABLE_COLUMNS: tuple[tuple[str, str], ...] = (
    ("id", "id"),
    ("name", "name"),
    ("local_domain", "domain"),
    ("project_path", "project"),
    ("web_root_display", "web root"),
    ("php_version", "php"),
    ("status", "status"),
)

RUNTIME_TABLE_COLUMNS: tuple[tuple[str, str], ...] = (
    ("version", "version"),
    ("label", "label"),
    ("home", "home"),
    ("source", "source"),
    ("removable", "removable"),
)

PHP_TABLE_COLUMNS: tuple[tuple[str, str], ...] = (
    ("version", "version"),
    ("label", "label"),
    ("home", "home"),
)

DATABASE_TABLE_COLUMNS: tuple[tuple[str, str], ...] = (
    ("id", "id"),
    ("engine", "engine"),
    ("version", "version"),
    ("label", "label"),
    ("home", "home"),
)

COMMAND_HELP: dict[str, dict[str, Any]] = {
    "server-engine": {
        "description": "Manage the Server Engine stack and isolated runtime inventories through the command-line.",
        "synopsis": "server-engine <command>",
        "subcommands": [
            ("stack", "Starts, stops, restarts, and inspects stack services."),
            ("site", "Creates, lists, shows, and removes site mappings."),
            ("config", "Prints configuration paths and server config data."),
            ("settings", "Shows application settings."),
            ("php", "Lists managed PHP runtimes."),
            ("runtime", "Lists, clears, and rebuilds managed runtime inventories."),
            ("node", "Lists or rebuilds the managed Node runtime inventory."),
            ("database", "Lists database runtimes and metadata."),
        ],
    },
    "server-engine stack": {
        "description": "Manage stack services.",
        "synopsis": "server-engine stack <start|stop|restart|status|paths> [service_id]",
        "subcommands": [
            ("start", "Starts a service or the full stack."),
            ("stop", "Stops a service or the full stack."),
            ("restart", "Restarts a service or the full stack."),
            ("status", "Shows service status."),
            ("paths", "Prints stack runtime paths."),
        ],
    },
    "server-engine site": {
        "description": "Manage site mappings.",
        "synopsis": "server-engine site <list|show|remove|add>",
        "subcommands": [
            ("list", "Lists site mappings."),
            ("show", "Shows a single site mapping."),
            ("remove", "Removes a site mapping."),
            ("add", "Creates a new site mapping."),
        ],
    },
    "server-engine config": {
        "description": "Inspect configuration paths and server config metadata.",
        "synopsis": "server-engine config <paths|apache>",
        "subcommands": [
            ("paths", "Prints all runtime paths."),
            ("apache", "Prints Apache runtime paths."),
        ],
    },
    "server-engine settings": {
        "description": "Inspect application settings.",
        "synopsis": "server-engine settings show",
        "subcommands": [
            ("show", "Shows current application settings."),
        ],
    },
    "server-engine php": {
        "description": "Manage PHP runtimes.",
        "synopsis": "server-engine php list",
        "subcommands": [
            ("list", "Lists managed PHP runtimes."),
        ],
    },
    "server-engine runtime": {
        "description": "Manage runtime inventories.",
        "synopsis": "server-engine runtime <list|clear|rebuild> [kind|all]",
        "subcommands": [
            ("list", "Lists runtime inventory entries."),
            ("clear", "Clears cached runtime inventory without rescanning."),
            ("rebuild", "Clears and rebuilds runtime inventory."),
        ],
    },
    "server-engine node": {
        "description": "Manage the Node runtime inventory.",
        "synopsis": "server-engine node <list|rebuild>",
        "subcommands": [
            ("list", "Lists managed Node runtimes."),
            ("rebuild", "Clears and rebuilds the Node runtime inventory."),
        ],
    },
    "server-engine database": {
        "description": "Inspect database runtimes and metadata.",
        "synopsis": "server-engine database <list|show>",
        "subcommands": [
            ("list", "Lists database runtimes."),
            ("show", "Shows database runtime metadata."),
        ],
    },
}


def _print_payload(payload: Any, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, indent=2))
        return
    if isinstance(payload, list):
        for item in payload:
            if isinstance(item, dict):
                print(" | ".join(f"{key}={value}" for key, value in item.items()))
            else:
                print(item)
        return
    if isinstance(payload, dict):
        for key, value in payload.items():
            print(f"{key}: {value}")
        return
    print(payload)


def _stringify(value: Any) -> str:
    if isinstance(value, bool):
        return "yes" if value else "no"
    if value is None:
        return ""
    return str(value)


def _print_table(items: list[dict[str, Any]], columns: tuple[tuple[str, str], ...]) -> None:
    if not items:
        print("(none)")
        return
    headers = [label for _, label in columns]
    rows: list[list[str]] = []
    widths = [len(label) for label in headers]
    for item in items:
        row = [_stringify(item.get(key, "")) for key, _label in columns]
        rows.append(row)
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))
    border = "+" + "+".join("-" * (width + 2) for width in widths) + "+"
    header_row = "| " + " | ".join(headers[index].ljust(widths[index]) for index in range(len(headers))) + " |"
    print(border)
    print(header_row)
    print(border)
    for row in rows:
        print("| " + " | ".join(row[index].ljust(widths[index]) for index in range(len(headers))) + " |")
    print(border)


def _print_list(payload: list[Any], as_json: bool, *, columns: tuple[tuple[str, str], ...] | None = None) -> None:
    if as_json:
        print(json.dumps(payload, indent=2))
        return
    if columns is not None and all(isinstance(item, dict) for item in payload):
        _print_table([dict(item) for item in payload], columns)
        return
    for item in payload:
        if isinstance(item, dict):
            print(" | ".join(f"{key}={value}" for key, value in item.items()))
        else:
            print(item)


def _runtime_inventory(container, kind: str) -> list[dict[str, Any]]:
    return container.runtime_inventory_service.clear_and_rebuild(kind)


def _runtime_inventory_map(container) -> dict[str, list[dict[str, Any]]]:
    return {kind: _runtime_inventory(container, kind) for kind in RUNTIME_KINDS}


def _help_key(*parts: str) -> str:
    cleaned = " ".join(part.strip() for part in parts if part.strip())
    return cleaned


def _print_help_block(name: str, description: str, synopsis: str, subcommands: list[tuple[str, str]]) -> None:
    print("NAME")
    print()
    print(f"  {name}")
    print()
    print("DESCRIPTION")
    print()
    print(f"  {description}")
    print()
    print("SYNOPSIS")
    print()
    print(f"  {synopsis}")
    if subcommands:
        print()
        print("SUBCOMMANDS")
        print()
        width = max(len(command) for command, _ in subcommands)
        for command, summary in subcommands:
            print(f"  {command.ljust(width)}  {summary}")


def _print_help_for(command: str, subcommand: str | None = None) -> None:
    key = command if subcommand is None else f"{command} {subcommand}"
    info = COMMAND_HELP.get(key)
    if info is None:
        info = COMMAND_HELP["server-engine"]
        key = "server-engine"
    _print_help_block(
        name=key,
        description=str(info["description"]),
        synopsis=str(info["synopsis"]),
        subcommands=list(info.get("subcommands", [])),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="server-engine")
    parser.add_argument("--json", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    stack_parser = subparsers.add_parser("stack")
    stack_subparsers = stack_parser.add_subparsers(dest="action", required=True)
    for action in ("start", "stop", "restart", "status"):
        action_parser = stack_subparsers.add_parser(action)
        action_parser.add_argument("service_id", nargs="?")
    stack_subparsers.add_parser("paths")

    site_parser = subparsers.add_parser("site")
    site_subparsers = site_parser.add_subparsers(dest="action", required=True)
    site_subparsers.add_parser("list")
    show_parser = site_subparsers.add_parser("show")
    show_parser.add_argument("site_id")
    remove_parser = site_subparsers.add_parser("remove")
    remove_parser.add_argument("site_id")
    add_parser = site_subparsers.add_parser("add")
    add_parser.add_argument("--name", required=True)
    add_parser.add_argument("--domain", required=True)
    add_parser.add_argument("--project-path", required=True)
    add_parser.add_argument("--web-root", default="public")
    add_parser.add_argument("--php-version", default="8.3")
    add_parser.add_argument("--database-enabled", action="store_true")
    add_parser.add_argument("--database-name")
    add_parser.add_argument("--database-user")
    add_parser.add_argument("--notes", default="")
    add_parser.add_argument("--tags", nargs="*", default=[])

    config_parser = subparsers.add_parser("config")
    config_subparsers = config_parser.add_subparsers(dest="action", required=True)
    config_subparsers.add_parser("paths")
    config_subparsers.add_parser("apache")

    settings_parser = subparsers.add_parser("settings")
    settings_subparsers = settings_parser.add_subparsers(dest="action", required=True)
    settings_subparsers.add_parser("show")

    php_parser = subparsers.add_parser("php")
    php_subparsers = php_parser.add_subparsers(dest="action", required=True)
    php_subparsers.add_parser("list")

    runtime_parser = subparsers.add_parser("runtime")
    runtime_subparsers = runtime_parser.add_subparsers(dest="action", required=True)
    runtime_list_parser = runtime_subparsers.add_parser("list")
    runtime_list_parser.add_argument("kind", nargs="?", default="all")
    runtime_clear_parser = runtime_subparsers.add_parser("clear")
    runtime_clear_parser.add_argument("kind", nargs="?", default="all")
    runtime_rebuild_parser = runtime_subparsers.add_parser("rebuild")
    runtime_rebuild_parser.add_argument("kind", nargs="?", default="all")

    node_parser = subparsers.add_parser("node")
    node_subparsers = node_parser.add_subparsers(dest="action", required=True)
    node_subparsers.add_parser("list")
    node_subparsers.add_parser("rebuild")

    database_parser = subparsers.add_parser("database")
    database_subparsers = database_parser.add_subparsers(dest="action", required=True)
    database_subparsers.add_parser("list")
    database_subparsers.add_parser("show")

    help_parser = subparsers.add_parser("help")
    help_parser.add_argument("topic", nargs="?", choices=["stack", "site", "config", "settings", "php", "runtime", "node", "database"])
    help_parser.add_argument("subtopic", nargs="?")

    return parser


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        raw_argv = list(sys.argv[1:])
    else:
        raw_argv = list(argv)
    if raw_argv and raw_argv[0] == "se":
        raw_argv = raw_argv[1:]
    parser = build_parser()
    json_output = False
    filtered_argv: list[str] = []
    for token in raw_argv:
        if token == "--json":
            json_output = True
            continue
        filtered_argv.append(token)
    if filtered_argv and filtered_argv[0] == "help":
        topic = filtered_argv[1] if len(filtered_argv) > 1 else None
        subtopic = filtered_argv[2] if len(filtered_argv) > 2 else None
        if topic is None:
            _print_help_for("server-engine")
            return 0
        if subtopic is None:
            _print_help_for(f"server-engine {topic}")
            return 0
        _print_help_for(f"server-engine {topic}", subtopic)
        return 0

    args = parser.parse_args(filtered_argv)
    args.json = bool(getattr(args, "json", False) or json_output)
    container = build_container()

    if args.command == "stack":
        if args.action == "paths":
            _print_payload(container.stack_service.apache_runtime_paths(), args.json)
            return 0
        if args.action == "start":
            payload = container.stack_service.start_service(args.service_id).to_dict() if args.service_id else container.stack_service.start_all().to_dict()
        elif args.action == "stop":
            payload = container.stack_service.stop_service(args.service_id).to_dict() if args.service_id else container.stack_service.stop_all().to_dict()
        elif args.action == "restart":
            if args.service_id:
                container.stack_service.stop_service(args.service_id)
                payload = container.stack_service.start_service(args.service_id).to_dict()
            else:
                payload = container.stack_service.restart_all().to_dict()
        else:
            payload = container.stack_service.status().to_dict() if not args.service_id else container.stack_service._status_for(container.stack_service._definition(args.service_id)).to_dict()
        _print_payload(payload, args.json)
        return 0

    if args.command == "site":
        if args.action == "list":
            payload = [site.to_dict() for site in container.site_service.list_sites()]
            _print_list(payload, args.json, columns=SITE_TABLE_COLUMNS)
            return 0
        if args.action == "show":
            site = container.site_service.get_site(args.site_id)
            if site is None:
                raise SystemExit(f"Site not found: {args.site_id}")
            _print_payload(site.to_dict(), args.json)
            return 0
        if args.action == "remove":
            removed = container.site_service.delete_site(args.site_id)
            _print_payload({"removed": removed, "site_id": args.site_id}, args.json)
            return 0
        site = container.site_service.create_site(
            name=args.name,
            local_domain=args.domain,
            project_path=args.project_path,
            web_root=args.web_root,
            php_version=args.php_version,
            database_enabled=args.database_enabled,
            database_name=args.database_name,
            database_user=args.database_user,
            notes=args.notes,
            tags=args.tags,
        )
        _print_payload(site.to_dict(), args.json)
        return 0

    if args.command == "config":
        payload = container.runtime_paths.to_dict() if args.action == "paths" else container.stack_service.apache_runtime_paths()
        _print_payload(payload, args.json)
        return 0

    if args.command == "settings":
        settings = container.settings_service.get_settings()
        payload = settings.to_dict()
        _print_payload(payload, args.json)
        return 0

    if args.command == "php":
        payload = [runtime.to_dict() for runtime in container.php_runtime_service.list_runtimes()]
        _print_list(payload, args.json, columns=PHP_TABLE_COLUMNS)
        return 0

    if args.command == "runtime":
        kind = str(args.kind).strip().lower()
        if args.action == "clear":
            if kind == "all":
                container.runtime_inventory_service.clear_all()
                payload: Any = {"cleared": "all"}
            else:
                if kind not in RUNTIME_KINDS:
                    raise SystemExit(f"Unknown runtime kind: {kind}")
                container.runtime_inventory_service.clear(kind)
                payload = {"cleared": kind}
            _print_payload(payload, args.json)
            return 0
        if kind == "all":
            if args.action == "rebuild":
                payload = _runtime_inventory_map(container)
            else:
                payload = _runtime_inventory_map(container)
        else:
            if kind not in RUNTIME_KINDS:
                raise SystemExit(f"Unknown runtime kind: {kind}")
            payload = _runtime_inventory(container, kind)
        _print_list(payload, args.json, columns=RUNTIME_TABLE_COLUMNS)
        return 0

    if args.command == "node":
        payload = _runtime_inventory(container, "node")
        _print_list(payload, args.json, columns=RUNTIME_TABLE_COLUMNS)
        return 0

    if args.command == "database":
        if args.action == "list":
            payload = [runtime.to_dict() for runtime in container.database_runtime_service.list_runtimes()]
        else:
            payload = container.database_service.runtime_metadata()
        if isinstance(payload, list):
            _print_list(payload, args.json, columns=DATABASE_TABLE_COLUMNS)
        else:
            _print_payload(payload, args.json)
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
