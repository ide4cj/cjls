#!/usr/bin/env python3


import shutil
from functools import cache
import os
import argparse
import subprocess
from dataclasses import dataclass
from pathlib import Path, PurePath
from typing import List
import sys


def remove_empty_files(dir: Path):
    for p in dir.rglob("*"):
        if p.is_file() and p.stat().st_size == 0:
            p.unlink()


MODULES_DIR = PurePath("modules")
CANGJIE_STDX_PATH = os.environ.get("CANGJIE_STDX_PATH")


@dataclass(frozen=True)
class PackageData:
    fqn: str

    @cache
    def src_dir(self) -> PurePath:
        module = self.module()
        module_src_dir = MODULES_DIR / module / "src"
        for s in self._segments()[1:]:
            module_src_dir /= s

        return module_src_dir

    def module(self) -> str:
        return self._segments()[0]

    @cache
    def _segments(self) -> List[str]:
        return self.fqn.split(".")


pkgs_with_derive_python = [
    PackageData("cjformat"),
    PackageData("cjmcp"),
    PackageData("ginkgo"),
    PackageData("project_model"),
    PackageData("loupe"),
    PackageData("loupe.db"),
    PackageData("loupe.hir"),
    PackageData("loupe.vfs"),
    PackageData("source_change"),
]


def cjpydoc_args_for_pkg(pkg: PackageData) -> List[str]:
    return [
        "cjpydoc",
        *[f"--python-package-source={source.fqn}={source.src_dir()}"
          for source in pkgs_with_derive_python],
        "--import-path=target/release",
        f"--import-path={CANGJIE_STDX_PATH}",
        "-Woff",
        "all",
        "-p",
        f"{pkg.src_dir()}",
    ]


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output-dir", type=Path, default=Path("./output"))

    args = parser.parse_args(argv)
    output_dir: Path = args.output_dir

    processes = []
    for pkg in pkgs_with_derive_python:
        proc = subprocess.Popen(cjpydoc_args_for_pkg(pkg), text=True)
        processes.append(proc)

    output_dir.mkdir(parents=True, exist_ok=True)
    status = 0
    for i, pkg in enumerate(pkgs_with_derive_python):
        if processes[i].wait() != 0:
            print(f"error: cjpydoc for package `{pkg.fqn}` failed", file=sys.stderr)
            status = 1
            continue
        cjpydoc_pkg_output_dir = Path(pkg.fqn)

        if not cjpydoc_pkg_output_dir.exists() or not cjpydoc_pkg_output_dir.is_dir():
            print(f"error: cjpydoc for package `{pkg.fqn}` produced no directory", file=sys.stderr)
            status = 1
            continue

        remove_empty_files(cjpydoc_pkg_output_dir)
        if not any(cjpydoc_pkg_output_dir.iterdir()):
            cjpydoc_pkg_output_dir.rmdir()
            continue

        dist_pkg_pyi_dir = output_dir / cjpydoc_pkg_output_dir
        if dist_pkg_pyi_dir.exists():
            shutil.rmtree(dist_pkg_pyi_dir)

        cjpydoc_pkg_output_dir.move_into(output_dir)

    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
