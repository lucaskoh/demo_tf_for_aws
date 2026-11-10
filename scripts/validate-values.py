#!/usr/bin/env python3
"""Validates values.yaml files (and the EC2 template registry) against their JSON Schema.

An environment (envs/<name>/) is made of two kinds of file: values.yaml (platform settings) and the files
under apps/ (workloads, instances and backends of the teams, any number, also in sub-folders). Besides the
shape of each file, the validator checks across the files of an environment: a name may be defined once,
only *.yaml files are read from apps/, and there is at least one backend.

Usage:
  scripts/validate-values.py                      every environment under envs/ and templates/ec2/templates.yaml
  scripts/validate-values.py envs/demo            one environment (a folder)
  scripts/validate-values.py FILE [FILE ...]      only these files (the kind comes from the path)
  scripts/validate-values.py --kind apps FILE     force the schema (values, apps or templates)

The schema checks the shape: unknown keys, types, ranges, enums, patterns, required fields.
What needs other data (a backend points to an existing workload, unique paths and numbers,
the EC2 template exists) is checked by Terraform when the network layer is planned.

Errors are printed as "file:line: path: message". Under GitHub Actions they are printed as
workflow commands instead, so they show up on the pull request. Exit code 1 on any error.
"""

import argparse
import difflib
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
    from jsonschema import Draft202012Validator
except ImportError as exc:  # pragma: no cover
    sys.exit(f"Missing Python package '{exc.name}'. Install with: python3 -m pip install -r scripts/requirements.txt")

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = {
    "values": ROOT / "schemas" / "values.schema.json",
    "apps": ROOT / "schemas" / "apps.schema.json",
    "templates": ROOT / "schemas" / "ec2-templates.schema.json",
}
IN_GITHUB_ACTIONS = os.environ.get("GITHUB_ACTIONS") == "true"

# Validators for which the schema's "x-error-message" is used instead of the generic text.
# (For "required" the schema is the whole object, so its message would not fit.)
CUSTOM_MESSAGE_FOR = {"pattern", "oneOf"}

# Which file a top-level section belongs to; used to say where a misplaced section should go
USER_SECTIONS = {"workloads": "workload", "instances": "instance", "backends": "backend"}
PLATFORM_SECTIONS = {"common", "network", "compute"}


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def walk(node, steps):
    """Follow `steps` from a YAML node. Returns (line of the last key or item, node)."""
    line = node.start_mark.line + 1
    for step in steps:
        if isinstance(node, yaml.MappingNode):
            for key_node, value_node in node.value:
                if str(key_node.value) == str(step):
                    line, node = key_node.start_mark.line + 1, value_node
                    break
            else:
                return line, node
        elif isinstance(node, yaml.SequenceNode) and isinstance(step, int) and step < len(node.value):
            node = node.value[step]
            line = node.start_mark.line + 1
        else:
            return line, node
    return line, node


def key_line(node, steps, key):
    """Line of `key` inside the mapping found at `steps`."""
    _, parent = walk(node, steps)
    if isinstance(parent, yaml.MappingNode):
        for key_node, _ in parent.value:
            if str(key_node.value) == str(key):
                return key_node.start_mark.line + 1
    return parent.start_mark.line + 1


def duplicate_keys(node, steps=()):
    """Yield (line, path, key) for every key that appears twice in the same mapping."""
    if isinstance(node, yaml.MappingNode):
        seen = set()
        for key_node, value_node in node.value:
            key = str(key_node.value)
            if key in seen:
                yield key_node.start_mark.line + 1, steps, key
            seen.add(key)
            yield from duplicate_keys(value_node, steps + (key,))
    elif isinstance(node, yaml.SequenceNode):
        for index, item in enumerate(node.value):
            yield from duplicate_keys(item, steps + (index,))


def show(value):
    return repr(value) if isinstance(value, (str, int, float, bool)) or value is None else None


def explain(error, root, kind="values"):
    """Turn one jsonschema error into [(line, path, message)]."""
    steps = list(error.path)
    path = ".".join(str(s) for s in steps) or "(top level)"

    if error.validator == "additionalProperties" and isinstance(error.instance, dict):
        allowed = list(error.schema.get("properties", {}))
        out = []
        for key in error.instance:
            if key in allowed:
                continue
            if not steps and kind == "values" and key in USER_SECTIONS:
                out.append((key_line(root, steps, key), path, f"'{key}' is declared in the files under envs/<environment>/apps/, not in values.yaml (platform settings)"))
                continue
            if not steps and kind == "apps" and key in PLATFORM_SECTIONS:
                out.append((key_line(root, steps, key), path, f"'{key}' belongs in values.yaml of the environment, not in a file under apps/"))
                continue
            hint = difflib.get_close_matches(str(key), allowed, n=1)
            text = f"unknown key '{key}'"
            text += f" - did you mean '{hint[0]}'?" if hint else ""
            text += f" (allowed here: {', '.join(allowed)})" if allowed else ""
            out.append((key_line(root, steps, key), path, text))
        return out

    line, node = walk(root, steps)

    # A property name that does not match "propertyNames": the error points at the mapping
    # but the failing instance is the name itself.
    if isinstance(node, yaml.MappingNode) and isinstance(error.instance, str) and error.instance in [
        str(k.value) for k, _ in node.value
    ]:
        line = key_line(root, steps, error.instance)
        path = ".".join([*(str(s) for s in steps), error.instance])

    custom = error.schema.get("x-error-message") if isinstance(error.schema, dict) else None
    if custom and error.validator in CUSTOM_MESSAGE_FOR:
        text = custom
        value = show(error.instance)
        if value is not None and error.validator == "pattern":
            text += f" (got {value})"
    else:
        text = error.message
        if len(text) > 160:
            text = text[:157] + "..."
    return [(line, path, text)]


def validate_file(path: Path, kind: str):
    """Return a list of (line, path, message)."""
    text = path.read_text()
    try:
        root = yaml.compose(text)
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        return [((mark.line + 1) if mark else 1, "(file)", f"not valid YAML: {getattr(exc, 'problem', exc)}")]
    if root is None:
        return [(1, "(file)", "the file is empty")]

    schema = json.loads(SCHEMAS[kind].read_text())
    errors = []

    for line, steps, key in duplicate_keys(root):
        errors.append((line, ".".join(str(s) for s in steps) or "(top level)", f"duplicate key '{key}' (the last one would silently win)"))

    for error in Draft202012Validator(schema).iter_errors(data):
        errors.extend(explain(error, root, kind))

    # scripts/tf.sh reads these two values with awk (scripts/common-value.sh), not with a YAML
    # parser. If the file is written in a way awk does not understand, the backend would get an
    # empty or a wrong value, so compare both readers.
    if kind == "values" and not errors and isinstance(data, dict) and isinstance(data.get("common"), dict):
        for key in ("state_bucket", "region", "platform_version"):
            expected = data["common"].get(key)
            if not isinstance(expected, str):
                continue  # (platform_version is optional: nothing to compare when it is absent)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts" / "common-value.sh"), str(path), key],
                capture_output=True,
                text=True,
            )
            got = result.stdout.strip()
            if got != expected:
                errors.append((
                    key_line(root, ["common"], key),
                    f"common.{key}",
                    f"scripts/tf.sh reads this value with awk and gets '{got}' instead of '{expected}'. "
                    f"Write it as '{key}: <value>' on one line directly under 'common:', "
                    "and do not repeat the key name in a nested map above it",
                ))

    # Platform-side check for the template registry: the boot script must exist.
    if kind == "templates" and isinstance(data, dict):
        for name, template in data.items():
            file_name = template.get("user_data_file") if isinstance(template, dict) else None
            if isinstance(file_name, str) and not (path.parent / file_name).is_file():
                errors.append((key_line(root, [name], "user_data_file"), f"{name}.user_data_file", f"file '{file_name}' does not exist next to {path.name}"))

    return sorted(set(errors))


def environment_files(env_dir: Path):
    """The files of one environment: values.yaml (platform) and the files under apps/ (teams)."""
    targets = []
    if (env_dir / "values.yaml").is_file():
        targets.append((env_dir / "values.yaml", "values"))
    targets += [(f, "apps") for f in sorted((env_dir / "apps").glob("**/*.yaml"))]
    return targets


def default_targets():
    targets = []
    for env_dir in sorted(p for p in (ROOT / "envs").iterdir() if p.is_dir()):
        targets += environment_files(env_dir)
    registry = ROOT / "templates" / "ec2" / "templates.yaml"
    if registry.is_file():
        targets.append((registry, "templates"))
    return targets


def kind_of(path: Path, forced=None):
    if forced:
        return forced
    if path.name == "templates.yaml":
        return "templates"
    return "apps" if "apps" in path.parts[:-1] else "values"


def environment_errors(env_dir: Path):
    """Checks across the files of one environment. Returns {path: [(line, where, message)]}."""
    found = {}  # (kind, name) -> [(path, line)]
    errors = {}
    backends = 0
    apps = env_dir / "apps"

    for path, _ in environment_files(env_dir):
        if path.name == "values.yaml":
            continue
        try:
            root = yaml.compose(path.read_text())
        except yaml.YAMLError:
            continue  # reported by the shape check of the file
        if not isinstance(root, yaml.MappingNode):
            continue
        for section_key, section in root.value:
            kind = USER_SECTIONS.get(str(section_key.value))
            if kind and isinstance(section, yaml.MappingNode):
                for name_node, _ in section.value:
                    found.setdefault((kind, str(name_node.value)), []).append((path, name_node.start_mark.line + 1))
                    backends += kind == "backend"

    for (kind, name), places in sorted(found.items()):
        if len(places) > 1:
            where = ", ".join(f"{rel(p)}:{line}" for p, line in places)
            for path, line in places:
                errors.setdefault(path, []).append((line, f"{kind}s.{name}", f"{kind} '{name}' is defined more than once in the environment ({where}); a name may be defined once"))

    if apps.is_dir():
        for f in sorted(p for p in apps.rglob("*") if p.is_file() and p.suffix != ".yaml"):
            errors.setdefault(f, []).append((1, "(file)", "only files that end in .yaml are read from apps/; this one is ignored (rename it)"))

    if env_dir.is_dir() and (env_dir / "values.yaml").is_file() and backends == 0:
        errors.setdefault(env_dir / "values.yaml", []).append((1, "(environment)", "the files under apps/ declare no backend; an environment needs at least one"))

    return errors


def escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def report(path: Path, errors):
    for line, where, message in errors:
        if IN_GITHUB_ACTIONS:
            print(f"::error file={escape(rel(path))},line={line}::{escape(where)}: {escape(message)}")
        else:
            print(f"{rel(path)}:{line}: {where}: {message}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--kind", choices=sorted(SCHEMAS), help="schema for the given files (default: from the path)")
    args = parser.parse_args()

    env_dirs = []
    if args.paths:
        targets = []
        for p in args.paths:
            if p.is_dir():
                env_dirs.append(p)
                targets += environment_files(p)
            else:
                targets.append((p, kind_of(p, args.kind)))
    else:
        targets = default_targets()
        env_dirs = sorted(p for p in (ROOT / "envs").iterdir() if p.is_dir())
    if not targets and not env_dirs:
        sys.exit("No files to validate.")

    failed = 0
    problems = {}
    for path, kind in targets:
        if not path.is_file():
            print(f"{rel(path)}: file not found", file=sys.stderr)
            failed += 1
            continue
        problems.setdefault(path, []).extend(validate_file(path, kind))
    for env_dir in env_dirs:
        for path, errors in environment_errors(env_dir).items():
            problems.setdefault(path, []).extend(errors)

    seen = set()
    for path, _ in targets:
        if path in seen:
            continue
        seen.add(path)
        errors = sorted(set(problems.get(path, [])))
        if errors:
            failed += len(errors)
            report(path, errors)
        elif path.is_file():
            print(f"ok    {rel(path)}")
    for path, errors in problems.items():  # files that were not targets (for example an ignored .yml)
        if path not in seen:
            failed += len(errors)
            report(path, sorted(set(errors)))

    if failed:
        print(f"\n{failed} error(s).", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
