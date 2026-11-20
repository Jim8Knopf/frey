"""Shared test helpers: load Frey's variables and render its real templates.

Four test files each carried their own byte-identical copy of `trusted()` and
a near-identical `setUp` that loaded role defaults, globbed
inventory/group_vars/all, dropped secrets.yml and called `combine_vars`. Five
more re-derived the "render a .sh.j2 or .py.j2 and run it" dance. This is that
code, once.

Importing it from a role's own tests directory needs two lines, because CI
runs `unittest discover -s <dir>` and so only puts that directory on the
path:

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tests'))
    from freyharness import inventory_vars, render_template
"""
from pathlib import Path
import subprocess
import sys
import tempfile

from ansible.template import Templar, trust_as_template
from ansible.utils.vars import combine_vars
import yaml

ROOT = Path(__file__).resolve().parents[1]
GROUP_VARS = ROOT / 'inventory/group_vars/all'


def trusted(value):
    """Mark every string in a variable tree as a trusted template.

    ansible-core 2.19 made this necessary: a plain str is no longer rendered.
    """
    if isinstance(value, str):
        return trust_as_template(value)
    if isinstance(value, dict):
        return {k: trusted(v) for k, v in value.items()}
    if isinstance(value, list):
        return [trusted(v) for v in value]
    return value


def group_var_files():
    """Every inventory group_vars file a test may read.

    secrets.yml is excluded because it is vault ciphertext; any file that
    turns out to be encrypted is skipped rather than crashing the test, so a
    newly vaulted file does not break the suite.
    """
    out = []
    for path in sorted(GROUP_VARS.glob('*.yml')):
        if path.name == 'secrets.yml':
            continue
        if path.read_bytes().startswith(b'$ANSIBLE_VAULT;'):
            continue
        out.append(path)
    return out


def role_defaults(role):
    """One role's defaults/main.yml as a dict, or {} if it has none."""
    path = ROOT / 'roles' / role / 'defaults/main.yml'
    if not path.is_file():
        return {}
    return yaml.safe_load(path.read_text()) or {}


def inventory_vars(*roles, **extra):
    """Role defaults merged under inventory group_vars, as Ansible does it.

    merge=True reproduces `hash_behaviour = merge` from ansible.cfg, which is
    what lets inventory set some nested keys and inherit the rest from role
    defaults. Roles are loaded first so inventory wins, matching precedence.
    """
    variables = {}
    for role in roles:
        variables = combine_vars(variables, role_defaults(role), merge=True)
    for path in group_var_files():
        data = yaml.safe_load(path.read_text()) or {}
        variables = combine_vars(variables, data, merge=True)
    if extra:
        variables = combine_vars(variables, extra, merge=True)
    return variables


def templar(variables):
    """A Templar with every string in `variables` marked trusted.

    For tests that template an expression they built themselves - a `vars:`
    value lifted out of a task file, say - rather than a whole file.
    """
    return Templar(variables=trusted(variables))


def render_string(text, variables):
    """Render a template string against `variables`."""
    return templar(variables).template(trust_as_template(text))


def render_template(path, variables):
    """Render a real template from the repo, by path relative to the root."""
    return render_string((ROOT / path).read_text(), variables)


def render_yaml(path, variables):
    """Render a template and parse the result as YAML."""
    return yaml.safe_load(render_template(path, variables))


def render_to_file(path, variables, directory, name=None, mode=0o755):
    """Render a template into a real file on disk, and return its path.

    For the .sh.j2 and .py.j2 templates that are tested by running them.
    """
    target = Path(directory) / (name or Path(path).name.removesuffix('.j2'))
    target.write_text(render_template(path, variables))
    target.chmod(mode)
    return target


def stub_bin(directory, **commands):
    """Build a directory of fake executables and return it, for PATH.

    stub_bin(tmp, docker='echo stubbed', nmcli='exit 1') writes two scripts.
    Each body is a shell snippet; a `#!/bin/sh` line is added.
    """
    bindir = Path(directory) / 'bin'
    bindir.mkdir(parents=True, exist_ok=True)
    for name, body in commands.items():
        script = bindir / name
        script.write_text('#!/bin/sh\n' + body + '\n')
        script.chmod(0o755)
    return bindir


def run_script(script, env=None, stdin='', timeout=60):
    """Run a rendered script and return the CompletedProcess."""
    return subprocess.run(
        [str(script)], capture_output=True, text=True, input=stdin,
        env=env, timeout=timeout, check=False)


def load_py_template(path, variables, name='rendered'):
    """Render a .py.j2 template and import it as a module.

    Used by the tests that exercise a host script's own functions rather than
    running it end to end.
    """
    import importlib.util

    with tempfile.TemporaryDirectory() as tmp:
        target = render_to_file(path, variables, tmp, name=name + '.py', mode=0o644)
        spec = importlib.util.spec_from_file_location(name, target)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module
