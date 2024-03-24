#!/usr/bin/env python3

import os
from urllib.request import urlopen
import json
from tempfile import NamedTemporaryFile
from zipfile import ZipFile
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
    if os.environ.get('GITHUB_ACTIONS', 'false') == 'true':
        pass

    f = NamedTemporaryFile(prefix="oi", suffix="zip", delete=False)
    try:
        with ZipFile(f, 'w') as zf:
            for item in json.load(urlopen(f"https://judgedat.u-aizu.ac.jp/testcases/{pid}/header"))["headers"]:
                data = json.load(urlopen(f"https://judgedat.u-aizu.ac.jp/testcases/{pid}/{item['serial']}"))
                if any(data[key].endswith("..... (terminated because of the limitation)\n")
                       for key in ("in","out")):
                    continue

                zf.mkdir(item['name'])
                for key in ("in", "out"):
                    with zf.open(f"{item['name']}/{key}", "w") as b:
                        b.write(data[key].encode())
        zf.close()
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        move(f.name, filename)
    except:
        os.unlink(f.name)
        raise

def fetch(path):
    filename = os.path.splitext(os.path.join("tests", path))[0] + ".zip"
    try:
        return ZipFile(filename)
    except FileNotFoundError:
        _fetch(path, filename)
        return ZipFile(filename)

def _list_testcases(f):
    for name in f.namelist():
        if name.endswith("/"):
            yield name[:-1]

def list_testcases(path):
    with fetch(path) as f:
        for item in _list_testcases(f):
            print(item)

def judge(path, kcov, bin, *testcases):
    assert bin is not None
    error = False
    print("judging", path)
    basename = os.path.splitext(path)[0]

    with fetch(basename) as f:
        if not testcases:
            testcases = tuple(_list_testcases(f))
        for item in testcases:
            with f.open(f"{item}/in") as b:
                input = b.read()
            with f.open(f"{item}/out") as b:
                output = b.read()

            command = [bin]
            if kcov:
                dirname = os.path.join(kcov, basename, item)
                os.makedirs(dirname, exist_ok=True)
                command = ['kcov', "--exclude-path=/opt,/usr", dirname] + command

            stdout = run(command, input=input, capture_output=True, check=True).stdout
            if output == stdout:
                print("[AC]", item)
            else:
                print("[WA]", item)
                error = True
    assert not error, f"{path} failed"

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
    subparser.add_argument('testcases', nargs='*')

    args = parser.parse_args()
    if args.command == 'fetch':
        fetch(args.path)
    elif args.command == 'list':
        list_testcases(args.path)
    elif args.command == 'judge':
        judge(args.path, args.kcov, args.bin, *args.testcases)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
