#!/usr/bin/env python3

import os
from urllib.request import urlopen
import json
from tempfile import TemporaryDirectory
from shutil import move
from subprocess import run

def splitpath(path):
    parts = []
    while path:
        head, tail = os.path.split(path)
        parts.insert(0, tail)
        path = head
    return parts

TERMINATED = "..... (terminated because of the limitation)\n"

def _fetch(path, filename):
    parts = splitpath(path)
    assert parts[0] == 'AOJ'
    pid = parts[-1]

    with TemporaryDirectory(prefix="oi") as d:
        for item in json.load(urlopen(f"https://judgedat.u-aizu.ac.jp/testcases/{pid}/header"))["headers"]:
            data = json.load(urlopen(f"https://judgedat.u-aizu.ac.jp/testcases/{pid}/{item['serial']}"))
            if any(data[key].endswith("..... (terminated because of the limitation)\n")
                   for key in ("in","out")):
                continue
            os.mkdir(os.path.join(d, item['name']))
            for key in ("in", "out"):
                with open(os.path.join(d, item['name'], key), "w") as b:
                    b.write(data[key])
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        move(d, filename)

def fetch(path):
    path = os.path.splitext(path)[0]
    filename = os.path.join("tests", path)
    if not os.path.exists(filename):
        _fetch(path, filename)
    return filename

def _list_testcases(path):
    for d in os.listdir(path):
        if os.path.isdir(os.path.join(path, d)):
            yield d

def list_testcases(path):
    fetch(path)
    path = os.path.splitext(path)[0]
    filename = os.path.join("tests", path)
    for item in _list_testcases(filename):
        print(item)

def judge(path, kcov, bin, testcase):
    assert bin is not None
    path = os.path.splitext(path)[0]

    filename = os.path.join("tests", path, testcase)
    with open(os.path.join(filename, "in"), "rb") as b:
        input = b.read()
    with open(os.path.join(filename, "out"), "rb") as b:
        output = b.read()

    command = [bin]
    if kcov:
        dirname = os.path.join(kcov, path, testcase)
        os.makedirs(dirname, exist_ok=True)
        command = ['kcov', "--exclude-path=/opt,/usr", dirname] + command

    stdout = run(command, input=input, capture_output=True, check=True).stdout
    if output != stdout:
        quit(1)

def main():
    import argparse
    parser = argparse.ArgumentParser(prog=__file__)

    subparsers = parser.add_subparsers(dest='command', help='sub-command help')
    subparser = subparsers.add_parser('fetch')
    subparser.add_argument('path')

    subparser = subparsers.add_parser('list')
    subparser.add_argument('path')

    subparser = subparsers.add_parser('judge')
    subparser.add_argument('--kcov')
    subparser.add_argument('--bin')
    subparser.add_argument('path')
    subparser.add_argument('testcase')

    args = parser.parse_args()
    if args.command == 'fetch':
        fetch(args.path)
    elif args.command == 'list':
        list_testcases(args.path)
    elif args.command == 'judge':
        judge(args.path, args.kcov, args.bin, args.testcase)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
