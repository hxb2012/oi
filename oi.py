#!/usr/bin/env python3

import os
from subprocess import run

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
    parser.add_argument('--kcov')
    parser.add_argument('--bin')
    parser.add_argument('path')
    parser.add_argument('testcase')
    args = parser.parse_args()
    judge(args.path, args.kcov, args.bin, args.testcase)

if __name__ == '__main__':
    main()
