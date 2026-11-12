#!/usr/bin/env python3
"""Flag apt tasks in Ansible task files that would miss a freshly added repository.

After adding a source a role must refresh the cache without cache_valid_time
before the next apt task, else a cache refreshed minutes earlier (by role
common or cloud-init) counts as valid and the new packages are not found;
this broke the first deploy of kai1 on 2026-11-07.

Usage: apt_cache.py TASKFILE...
"""

import sys

import yaml

KNOWN_MODULES = (
    "apt",
    "ansible.builtin.apt",
    "apt_repository",
    "ansible.builtin.apt_repository",
    "deb822_repository",
    "ansible.builtin.deb822_repository",
    "copy",
    "ansible.builtin.copy",
    "template",
    "ansible.builtin.template",
)


def _get_module_name(task):
    """Return the first module of interest used by the task, or None."""
    for key in KNOWN_MODULES:
        if key in task:
            return key
    return None


def _get_module_args(task, module_name):
    """Return the module args dict for a given module name, or {} if not a dict."""
    args = task.get(module_name, {})
    if not isinstance(args, dict):
        return {}
    return args


def _is_apt_task(module_name):
    """Check if the module is an apt module (short or FQCN)."""
    return module_name in ("apt", "ansible.builtin.apt")


def _is_apt_repository_task(module_name):
    """Check if the module is an apt_repository module (short or FQCN)."""
    return module_name in ("apt_repository", "ansible.builtin.apt_repository")


def _is_deb822_repository_task(module_name):
    """Check if the module is a deb822_repository module (short or FQCN)."""
    return module_name in ("deb822_repository", "ansible.builtin.deb822_repository")


def _is_copy_or_template_task(module_name):
    """Check if the module is copy or template (short or FQCN)."""
    return module_name in (
        "copy",
        "template",
        "ansible.builtin.copy",
        "ansible.builtin.template",
    )


def _adds_source_without_refresh(task, module_name):
    """Determine if a task adds a source without cache refresh."""
    if _is_deb822_repository_task(module_name):
        return True

    if _is_apt_repository_task(module_name):
        args = _get_module_args(task, module_name)
        update_cache = args.get("update_cache", True)
        return bool(
            update_cache is False or update_cache == "false" or update_cache == "no"
        )

    if _is_apt_task(module_name):
        args = _get_module_args(task, module_name)
        return "deb" in args

    if _is_copy_or_template_task(module_name):
        args = _get_module_args(task, module_name)
        dest = args.get("dest", "")
        return bool(
            isinstance(dest, str) and dest.startswith("/etc/apt/sources.list.d")
        )

    return False


def _flatten_tasks(tasks):
    """Flatten block/rescue/always recursively, yielding task dicts."""
    for task in tasks:
        if not isinstance(task, dict):
            continue
        yield task
        for section in ("block", "rescue", "always"):
            if section in task and isinstance(task[section], list):
                yield from _flatten_tasks(task[section])


def _check_file(path):
    """Check a single task file for findings. Returns list of finding strings."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError) as e:
        print(f"Error reading {path}: {e}", file=sys.stderr)
        return None

    if not isinstance(data, list):
        return []

    findings = []
    pending = None

    for task in _flatten_tasks(data):
        module_name = _get_module_name(task)
        if module_name is None:
            continue

        task_name = task.get("name", "(unnamed)")

        # First: check if pending and current task is an apt task without key deb
        if pending is not None and _is_apt_task(module_name):
            args = _get_module_args(task, module_name)
            if "deb" not in args:
                update_cache = args.get("update_cache", False)
                has_cache_valid_time = "cache_valid_time" in args

                if (
                    update_cache is True
                    or update_cache == "true"
                    or update_cache == "yes"
                ) and not has_cache_valid_time:
                    pending = None
                else:
                    findings.append(
                        f"{path}: task '{task_name}' runs apt after '{pending}' "
                        f"added a source without a cache refresh; refresh first "
                        f"with update_cache: true and no cache_valid_time"
                    )
                    pending = None

        # Then: if current task adds a source without refresh, set pending
        if _adds_source_without_refresh(task, module_name):
            pending = task_name

    return findings


def main(argv):
    """Main entry point. Returns exit code: 0 clean, 1 findings, 2 usage/error."""
    if len(argv) < 2:
        print("Usage: apt_cache.py TASKFILE...", file=sys.stderr)
        return 2

    task_files = argv[1:]
    all_findings = []

    for path in task_files:
        findings = _check_file(path)
        if findings is None:
            return 2
        all_findings.extend(findings)

    for finding in all_findings:
        print(finding)

    if all_findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
