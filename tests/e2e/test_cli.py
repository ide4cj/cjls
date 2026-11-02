"""CLI dispatch must keep informational output separate from the default LSP session."""

import json
import subprocess

from conftest import CJLS


def test_help_exits_without_starting_the_server():
    # arrange
    command = [CJLS, "--help"]

    # act
    run = subprocess.run(command, capture_output=True, text=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr
    assert "Usage: cjls" in run.stdout
    assert "--config-schema" in run.stdout
    assert all(command in run.stdout for command in ["project", "fmt", "fetch-src"])
    assert run.stderr == ""


def test_config_schema_remains_a_standalone_json_document():
    # arrange
    command = [CJLS, "--config-schema"]

    # act
    run = subprocess.run(command, capture_output=True, text=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr
    schema = json.loads(run.stdout)
    assert schema["type"] == "object"
    assert "properties" in schema
    assert run.stderr == ""


def test_fmt_checks_relative_paths_then_formats_them(tmp_path):
    # arrange
    source = "func f(){let x=1}\n"
    files = [tmp_path / name for name in ["a.cj", "b.cj"]]
    for file in files:
        file.write_text(source)

    # act
    checked = subprocess.run(
        [CJLS, "fmt", "a.cj", "--check", "b.cj"],
        cwd=tmp_path,
        capture_output=True,
        timeout=60,
    )

    # assert
    assert checked.returncode == 1, checked.stderr.decode()
    assert all(file.read_text() == source for file in files)

    # act
    formatted = subprocess.run(
        [CJLS, "fmt", "a.cj", "b.cj"], cwd=tmp_path, capture_output=True, timeout=60
    )

    # assert
    assert formatted.returncode == 0, formatted.stderr.decode()
    assert all(file.read_text() == "func f() {\n    let x = 1\n}\n" for file in files)

    # act
    rechecked = subprocess.run(
        [CJLS, "fmt", "--check", "a.cj", "b.cj"],
        cwd=tmp_path,
        capture_output=True,
        timeout=60,
    )

    # assert
    assert rechecked.returncode == 0, rechecked.stderr.decode()
