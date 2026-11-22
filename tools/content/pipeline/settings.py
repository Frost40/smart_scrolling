"""Pipeline home, root secrets and validated settings overrides."""

import copy
import json
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[3]
DEFAULTS = Path(__file__).with_name("defaults.json")


def secrets():
    """Read root .env using the upload tool's parsing rules."""
    env = {}
    path = ROOT / ".env"
    if path.exists():
        with path.open(encoding="utf-8") as stream:
            for line in stream:
                if "=" in line and not line.lstrip().startswith("#"):
                    key, value = line.split("=", 1)
                    env[key.strip()] = value.strip().strip('"')
    return env


def home():
    """Create the pipeline home and its documented working folders."""
    folder = (os.environ.get("PIPELINE_HOME") or secrets().get("PIPELINE_HOME")
              or str(Path(os.environ.get("USERPROFILE") or Path.home()) / "SmartScrollingContent"))
    folder = Path(os.path.expandvars(folder)).expanduser()
    for name in ("state", "inbox", "probe", "sandbox", "jobs", "archive", "logs"):
        (folder / name).mkdir(parents=True, exist_ok=True)
    return folder


def _merge(base, changes, schema, provider_fields, path=""):
    if not isinstance(changes, dict):
        raise ValueError(f"{path or 'settings'}: expected an object")
    result = copy.deepcopy(base)
    for key, value in changes.items():
        here = f"{path}.{key}" if path else key
        if path == "providers":
            provider = _merge(base.get(key, {}), value, provider_fields, provider_fields, here)
            if key not in base:
                if not provider.get("driver"):
                    raise ValueError(f"{here}.driver: required")
                if not (provider.get("preset") or provider.get("base_url")):
                    raise ValueError(f"{here}: preset or base_url required")
            result[key] = provider
            continue
        if key not in schema:
            raise ValueError(f"{here}: unknown setting")
        if isinstance(schema[key], dict):
            result[key] = _merge(base.get(key, {}), value, schema[key], provider_fields, here)
        else:
            expected = type(schema[key])
            allowed = (int, float) if expected is float else (expected,)
            if path.startswith("stages.") and key == "run":
                allowed = (str, list)
                if isinstance(value, list) and not all(isinstance(arg, str) for arg in value):
                    raise ValueError(f"{here}: expected a list of command strings")
            if type(value) not in allowed:
                raise ValueError(f"{here}: expected {' or '.join(t.__name__ for t in allowed)}")
            result[key] = copy.deepcopy(value)
    return result


def _validated(changes):
    defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
    # Optional provider fields share one vocabulary, regardless of the provider's defaults.
    provider_fields = {key: value for provider in defaults["providers"].values()
                       for key, value in provider.items()}
    result = _merge(defaults, changes, defaults, provider_fields)
    for name, stage in result['stages'].items():
        for key in ('every_minutes', 'max_minutes'):
            if stage[key] <= 0:
                raise ValueError(f'stages.{name}.{key}: must be positive')
        hours = stage['hours']
        if len(hours) != 2 or any(type(h) is not int or not 0 <= h <= 24 for h in hours) or hours[0] > hours[1]:
            raise ValueError(f'stages.{name}.hours: expected [start, end] within 0..24')
        if stage['run'] != 'builtin' and (not isinstance(stage['run'], list) or not stage['run'] or not stage['run'][0]):
            raise ValueError(f'stages.{name}.run: expected builtin or a nonempty command list')
    if result['tick']['max_minutes'] <= 0:
        raise ValueError('tick.max_minutes: must be positive')
    if not 1 <= result['dashboard']['port'] <= 65535:
        raise ValueError('dashboard.port: must be within 1..65535')
    for role, names in result["roles"].items():
        for index, name in enumerate(names):
            if not isinstance(name, str) or name not in result["providers"]:
                raise ValueError(f"roles.{role}[{index}]: unknown provider")
    from .feeds import READERS
    from .gates import known_topics
    topics = known_topics()
    for feed in result['feeds']:
        if not isinstance(feed, dict) or set(feed) != {'reader', 'params', 'topics', 'per_day', 'enabled'}:
            raise ValueError('feeds: expected reader, params, topics, per_day and enabled')
        if feed['reader'] not in READERS or not isinstance(feed['params'], dict):
            raise ValueError('feeds: unknown reader or invalid params')
        if type(feed['per_day']) is not int or feed['per_day'] < 0 or type(feed['enabled']) is not bool:
            raise ValueError('feeds: per_day must be nonnegative and enabled must be boolean')
        if not isinstance(feed['topics'], list) or not feed['topics'] or any(not isinstance(t, str) or t not in topics for t in feed['topics']):
            raise ValueError('feeds: expected known topics')
    return result


def _overrides(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def load():
    """Recursively overlay home settings, rejecting unknown paths."""
    return _validated(_overrides(home() / "settings.json"))


def set_value(path, text):
    """Validate one edit before atomically replacing only the home settings file."""
    parts = path.split(".")
    if not all(parts):
        raise ValueError(f"{path!r}: invalid settings path")
    try:
        value = json.loads(text)
    except ValueError:
        value = text
        if len(parts) == 2 and parts[0] == "roles":
            value = [name.strip() for name in text.split(",")]
    target = home() / "settings.json"
    changes = _overrides(target)
    branch = changes
    for part in parts[:-1]:
        if not isinstance(branch, dict):
            raise ValueError(f"{path}: expected an object")
        branch = branch.setdefault(part, {})
    if not isinstance(branch, dict):
        raise ValueError(f"{path}: expected an object")
    branch[parts[-1]] = value
    _validated(changes)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=target.parent,
                                         prefix="settings-", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(changes, stream, indent=2, ensure_ascii=False, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
