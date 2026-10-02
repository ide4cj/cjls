"""`cjls project [--dir <dir>]`: the project found for a directory, the current one by default, written to stdout as cj-project.json (#69)."""

import json
import subprocess

from conftest import CJLS


def test_a_cjpm_project_is_printed_with_every_default_written_out(tmp_path):
    # arrange
    (tmp_path / "cjpm.toml").write_text('[package]\nname = "app"\n')
    (tmp_path / "src" / "util").mkdir(parents=True)
    (tmp_path / "src" / "main.cj").write_text("main() {}\n")
    (tmp_path / "src" / "util" / "u.cj").write_text("package app.util\n")

    # act
    run = subprocess.run([CJLS, "project"], cwd=tmp_path, capture_output=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr.decode()
    project = json.loads(run.stdout)
    module = project["modules"][0]
    assert module["name"] == "app"
    assert module["root"] == "src"
    assert [(p["name"], p["dir"], p["files"]) for p in module["packages"]] == [
        ("app", "src", ["main.cj"]),
        ("app.util", "src/util", ["u.cj"]),
    ]
    assert module["member"] is True
    assert set(project["cfg"]) >= {"os", "arch", "backend"}


def test_dir_names_the_directory(tmp_path):
    # arrange
    (tmp_path / "cjpm.toml").write_text('[package]\nname = "app"\n')

    # act
    run = subprocess.run([CJLS, "project", "--dir", str(tmp_path)], capture_output=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr.decode()
    assert json.loads(run.stdout)["modules"][0]["name"] == "app"


def test_an_unknown_command_is_a_usage_error():
    # act
    run = subprocess.run([CJLS, "frob"], capture_output=True, timeout=60)

    # assert
    assert run.returncode == 2
    assert run.stdout == b""
    assert "Usage: cjls" in run.stderr.decode()
