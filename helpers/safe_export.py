#!/usr/bin/env python3
"""Run a bounded ffmpeg export and replace its destination atomically."""

import errno
import os
import secrets
import signal
import stat
import subprocess
import sys
import time


EXPORT_TIMEOUT_SECONDS = 600
EXPORT_MAX_BYTES = 2 * 1024 * 1024 * 1024
UNSAFE_DESTINATION = 125
OUTPUT_TOO_LARGE = 126
EXPORT_TIMED_OUT = 124


def die(message, code=1):
    print(message, file=sys.stderr)
    return code


def open_parent(path):
    parent, name = os.path.split(path)
    if not os.path.isabs(path) or not parent or not name or name in (".", ".."):
        raise OSError(errno.EINVAL, "invalid export path")

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(parent, flags)
    directory_stat = os.fstat(directory_fd)
    if not stat.S_ISDIR(directory_stat.st_mode):
        os.close(directory_fd)
        raise OSError(errno.ENOTDIR, "export parent is not a directory")
    return directory_fd, name


def reject_unsafe_destination(directory_fd, name):
    try:
        destination_stat = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if not stat.S_ISREG(destination_stat.st_mode):
        raise OSError(errno.ELOOP, "export destination is not a regular file")


def create_temporary_output(directory_fd):
    # O_TMPFILE keeps the output unnamed while ffmpeg is running, so there is
    # no path that another process can replace with a symlink or FIFO.
    flags = os.O_RDWR | os.O_TMPFILE | os.O_CLOEXEC
    return_fd = os.open(".", flags, 0o600, dir_fd=directory_fd)
    file_stat = os.fstat(return_fd)
    if not stat.S_ISREG(file_stat.st_mode):
        os.close(return_fd)
        raise OSError(errno.EINVAL, "temporary export is not a regular file")
    return return_fd


def link_temporary_output(directory_fd, temporary_fd):
    source_path = "/proc/self/fd/{}".format(temporary_fd)
    for _ in range(10):
        name = ".omarchy-video-tools-{}.mp4".format(secrets.token_hex(16))
        try:
            os.link(source_path, name, dst_dir_fd=directory_fd, follow_symlinks=True)
            return name
        except FileExistsError:
            continue
    raise OSError(errno.EEXIST, "could not link an exclusive export temporary")


def terminate_process(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def run_export(
    directory_fd,
    temporary_fd,
    maximum_seconds,
    maximum_bytes,
    command,
):
    # The anonymous file descriptor is passed to ffmpeg through procfs. The
    # directory descriptor is also inherited for the final descriptor-relative
    # link and replace operations.
    temporary_path = "/proc/self/fd/{}".format(temporary_fd)
    process = subprocess.Popen(
        command + ["-y", "-f", "mp4", temporary_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        pass_fds=(directory_fd, temporary_fd),
        start_new_session=True,
    )
    started = time.monotonic()
    try:
        while True:
            file_size = os.fstat(temporary_fd).st_size
            if file_size > maximum_bytes:
                terminate_process(process)
                return OUTPUT_TOO_LARGE
            if time.monotonic() - started > maximum_seconds:
                terminate_process(process)
                return EXPORT_TIMED_OUT
            exit_code = process.poll()
            if exit_code is not None:
                return exit_code
            time.sleep(0.05)
    finally:
        terminate_process(process)


def export(output_path, maximum_seconds, maximum_bytes, command):
    directory_fd, destination_name = open_parent(output_path)
    staging_name = None
    temporary_fd = -1
    try:
        reject_unsafe_destination(directory_fd, destination_name)
        temporary_fd = create_temporary_output(directory_fd)
        exit_code = run_export(
            directory_fd,
            temporary_fd,
            maximum_seconds,
            maximum_bytes,
            command,
        )
        if exit_code != 0:
            return exit_code

        final_stat = os.fstat(temporary_fd)
        if not stat.S_ISREG(final_stat.st_mode):
            return die("temporary export is not a regular file", UNSAFE_DESTINATION)
        if final_stat.st_size > maximum_bytes:
            return die("export exceeded the output size limit", OUTPUT_TOO_LARGE)
        os.fsync(temporary_fd)
        staging_name = link_temporary_output(directory_fd, temporary_fd)
        os.close(temporary_fd)
        temporary_fd = -1
        os.replace(
            staging_name,
            destination_name,
            src_dir_fd=directory_fd,
            dst_dir_fd=directory_fd,
        )
        staging_name = None
        return 0
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        if staging_name is not None:
            try:
                os.unlink(staging_name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        os.close(directory_fd)


def main():
    if len(sys.argv) < 6:
        return die(
            "usage: safe_export.py MAX_SECONDS MAX_BYTES OUTPUT_PATH COMMAND [ARGUMENT ...]"
        )
    try:
        maximum_seconds = float(sys.argv[1])
        maximum_bytes = int(sys.argv[2])
    except ValueError:
        return die("export limits must be numeric")
    if maximum_seconds <= 0 or maximum_bytes <= 0:
        return die("export limits must be positive")
    try:
        return export(sys.argv[3], maximum_seconds, maximum_bytes, sys.argv[4:])
    except (OSError, ValueError) as error:
        return die("export rejected: {}".format(error), UNSAFE_DESTINATION)


if __name__ == "__main__":
    sys.exit(main())
