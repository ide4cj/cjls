"""CLI dispatch must keep informational output separate from the default LSP session."""

import json
import subprocess

import pytest

from conftest import CJLS


@pytest.mark.parametrize(
    "args, usage, option",
    [
        (["--help"], "Usage: cjls", "--config-schema"),
        (["-h"], "Usage: cjls", "--config-schema"),
        (["help"], "Usage: cjls", "--config-schema"),
        (["project", "--help"], "Usage: cjls project", "--dir"),
        (["help", "project"], "Usage: cjls project", "--dir"),
        (["fmt", "-h"], "Usage: cjls fmt", "--check"),
        (["help", "fmt"], "Usage: cjls fmt", "--check"),
        (["fetch-src", "--help"], "Usage: cjls fetch-src", "--dir"),
        (["help", "fetch-src"], "Usage: cjls fetch-src", "--dir"),
    ],
)
def test_help_exits_without_starting_the_server(args, usage, option):
    run = subprocess.run([CJLS, *args], capture_output=True, text=True, timeout=60)

    assert run.returncode == 0, run.stderr
    assert usage in run.stdout
    assert option in run.stdout
    assert run.stderr == ""


def test_config_schema_remains_a_standalone_json_document():
    run = subprocess.run(
        [CJLS, "--config-schema"], capture_output=True, text=True, timeout=60
    )

    assert run.returncode == 0, run.stderr
    schema = json.loads(run.stdout)
    assert schema["type"] == "object"
    assert "properties" in schema
    assert run.stderr == ""


@pytest.mark.parametrize("check", ["--check", "-c"])
def test_fmt_checks_relative_paths_then_formats_them(tmp_path, check):
    source = "func f(){let x=1}\n"
    files = [tmp_path / name for name in ["a.cj", "b.cj"]]
    for file in files:
        file.write_text(source)

    checked = subprocess.run(
        [CJLS, "fmt", "a.cj", check, "b.cj"],
        cwd=tmp_path,
        capture_output=True,
        timeout=60,
    )
    assert checked.returncode == 1, checked.stderr.decode()
    assert all(file.read_text() == source for file in files)

    formatted = subprocess.run(
        [CJLS, "fmt", "a.cj", "b.cj"], cwd=tmp_path, capture_output=True, timeout=60
    )
    assert formatted.returncode == 0, formatted.stderr.decode()
    assert all(file.read_text() != source for file in files)

    rechecked = subprocess.run(
        [CJLS, "fmt", check, "a.cj", "b.cj"],
        cwd=tmp_path,
        capture_output=True,
        timeout=60,
    )
    assert rechecked.returncode == 0, rechecked.stderr.decode()


@pytest.mark.parametrize(
    "args",
    [
        ["--dir", "sub"],
        ["--dir=sub"],
        ["-d", "sub"],
        ["-dsub"],
        ["--dir", "ignored", "-d", "sub"],
    ],
)
def test_project_resolves_directory_options_relative_to_cwd(tmp_path, args):
    project = tmp_path / "sub"
    project.mkdir()
    (project / "cjpm.toml").write_text('[package]\nname = "cli_test"\n')

    run = subprocess.run(
        [CJLS, "project", *args],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=60,
    )

    assert run.returncode == 0, run.stderr
    assert json.loads(run.stdout)["modules"][0]["name"] == "cli_test"
