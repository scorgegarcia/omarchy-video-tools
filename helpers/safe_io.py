#!/usr/bin/env python3
"""Descriptor-bound, bounded settings I/O for the video-tools plugin."""

import errno
import os
import stat
import sys


MAX_BYTES = 4096
NOT_REGULAR = getattr(errno, "EFTYPE", errno.EINVAL)


def die(message):
    print(message, file=sys.stderr)
    return 1


def open_parent(path):
    parent, name = os.path.split(path)
    if not parent or not name or name in (".", ".."):
        raise OSError(errno.EINVAL, "invalid settings path")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(parent, flags)
    directory_stat = os.fstat(directory_fd)
    if not stat.S_ISDIR(directory_stat.st_mode):
        os.close(directory_fd)
        raise OSError(errno.ENOTDIR, "settings parent is not a directory")
    return directory_fd, name


def read_settings(path):
    directory_fd, name = open_parent(path)
    try:
        flags = (
            os.O_RDONLY
            | os.O_CLOEXEC
            | os.O_NONBLOCK
            | getattr(os, "O_NOFOLLOW", 0)
        )
        file_fd = os.open(name, flags, dir_fd=directory_fd)
        try:
            file_stat = os.fstat(file_fd)
            if not stat.S_ISREG(file_stat.st_mode):
                raise OSError(NOT_REGULAR, "settings path is not a regular file")
            if file_stat.st_size > MAX_BYTES:
                raise OSError(errno.EFBIG, "settings file is too large")

            data = bytearray()
            while len(data) <= MAX_BYTES:
                chunk = os.read(file_fd, MAX_BYTES + 1 - len(data))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > MAX_BYTES:
                    raise OSError(errno.EFBIG, "settings file grew past the limit")
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        finally:
            os.close(file_fd)
    finally:
        os.close(directory_fd)
    return 0


def write_settings(path):
    data = sys.stdin.buffer.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        return die("settings payload is too large")

    directory_fd, name = open_parent(path)
    temporary_name = ".settings.json.tmp.{}".format(os.getpid())
    temporary_fd = -1
    try:
        flags = (
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | os.O_CLOEXEC
            | getattr(os, "O_NOFOLLOW", 0)
        )
        temporary_fd = os.open(temporary_name, flags, 0o600, dir_fd=directory_fd)
        temporary_stat = os.fstat(temporary_fd)
        if not stat.S_ISREG(temporary_stat.st_mode):
            raise OSError(NOT_REGULAR, "temporary settings path is not regular")

        offset = 0
        while offset < len(data):
            offset += os.write(temporary_fd, data[offset:])
        os.fsync(temporary_fd)
        os.close(temporary_fd)
        temporary_fd = -1
        os.replace(temporary_name, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        try:
            os.unlink(temporary_name, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
        os.close(directory_fd)
    return 0


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("read", "write"):
        return die("usage: safe_io.py read|write PATH")
    try:
        if sys.argv[1] == "read":
            return read_settings(sys.argv[2])
        return write_settings(sys.argv[2])
    except (OSError, ValueError) as error:
        return die("settings I/O rejected: {}".format(error))


if __name__ == "__main__":
    sys.exit(main())
