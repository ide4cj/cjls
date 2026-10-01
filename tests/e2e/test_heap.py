"""The heap the server runs on (D31): it starts over with 2 GB unless `cjHeapSize` is set."""

import os
import subprocess

from conftest import CJLS

GB = 1024 * 1024 * 1024


def started_with_heap(env: dict[str, str]) -> int:
    """The heap the server logged on start; stdin is empty, so it stops at once."""
    run = subprocess.run([CJLS], stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=60)
    started = [line for line in run.stderr.decode().splitlines() if " INFO started " in line]
    assert len(started) == 1, run.stderr.decode()
    return int(started[0].split("heap=")[1])


def test_a_server_started_without_a_heap_size_runs_on_2_gb():
    # arrange
    env = {k: v for k, v in os.environ.items() if k != "cjHeapSize"}

    # act
    heap = started_with_heap(env)

    # assert
    assert heap == 2 * GB


def test_a_heap_size_the_user_set_is_kept():
    # arrange
    env = dict(os.environ, cjHeapSize="512MB")

    # act
    heap = started_with_heap(env)

    # assert
    assert heap == GB // 2
