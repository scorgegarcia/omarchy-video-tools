#!/usr/bin/env python3
"""Run a command while forwarding at most a fixed number of stdout bytes."""

import os
import signal
import subprocess
import sys


def main():
    if len(sys.argv) < 3:
        print("usage: bounded_command.py MAX_BYTES COMMAND [ARGUMENT ...]", file=sys.stderr)
        return 2
    try:
        maximum = int(sys.argv[1])
    except ValueError:
        return 2
    if maximum <= 0:
        return 2

    process = subprocess.Popen(
        sys.argv[2:],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    output = bytearray()
    try:
        while len(output) < maximum:
            chunk = process.stdout.read(min(4096, maximum - len(output) + 1))
            if not chunk:
                break
            output.extend(chunk)
            if len(output) >= maximum:
                break
    finally:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=0.25)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
        else:
            process.wait()

    sys.stdout.buffer.write(output[:maximum])
    sys.stdout.buffer.flush()
    return process.returncode if process.returncode is not None else 1


if __name__ == "__main__":
    sys.exit(main())
