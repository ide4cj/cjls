"""The heap the server runs on (D31): it starts over with 2 GB unless `cjHeapSize` is set."""

import json
import os
import subprocess
import sys

import psutil

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


def serving(env: dict[str, str]) -> subprocess.Popen:
    """A server that has answered `initialize`: whatever process serves it is running by then."""
    server = subprocess.Popen([CJLS], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, env=env)
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                       "params": {"processId": None, "rootUri": None, "capabilities": {}}}).encode()
    server.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    server.stdin.flush()
    headers = b""
    while not headers.endswith(b"\r\n\r\n"):
        headers += server.stdout.read(1)
    length = int(headers.split(b"Content-Length:")[1].split(b"\r\n")[0])
    assert json.loads(server.stdout.read(length))["id"] == 1
    return server


def test_killing_the_server_leaves_no_process_of_it_behind():
    # arrange: on POSIX the server started over in its own process, on Windows in a child (D31)
    env = {k: v for k, v in os.environ.items() if k != "cjHeapSize"}
    server = serving(env)
    children = psutil.Process(server.pid).children(recursive=True)
    assert len(children) == (1 if sys.platform == "win32" else 0)

    # act: as an editor kills a server it gave up on, its end of stdin still open
    server.kill()
    server.wait()

    # assert: the child ends with it (D78); one left running would hold this until the timeout
    _, alive = psutil.wait_procs(children)
    assert alive == []
    server.stdin.close()
    server.stdout.close()
