#!/usr/bin/env python3

import argparse
import os
import re
from subprocess import Popen, PIPE, DEVNULL

args_parser = argparse.ArgumentParser(
    prog="minifier",
    description="Minifies",
)

args_parser.add_argument('variant')
args_parser.add_argument('resource')
args = args_parser.parse_args()

variant = args.variant
resource = args.resource

def safemkdir(dir):
    try:
        os.mkdir(dir)
    except:
        pass

match variant:
    case "dependency":
        dependency_pattern = re.compile("^((?P<path>.+)\\/)?(?P<dependency>[\\w\\.]+)$")
        groups = dependency_pattern.search(resource).groupdict()
        dependency = groups.get('dependency')
        dependency_path = dependency.replace('.', '/')
        dev_path = f"{dependency_path}.lua"
        subpath = groups.get('path')
        if subpath:
            path = f"dependencies/{subpath}/{dev_path}"
        else:
            path = f"dependencies/{dev_path}"
        out_dir = f"out/dependencies"
        in_file = path
        resource = dependency_path
    case "installer":
        out_dir = f"out/installers"
        in_file = f"distributions/{resource}/installer.lua"
    case "entrypoint":
        out_dir = f"out/entrypoints"
        in_file = f"distributions/{resource}/main.lua"
    case _:
        raise ValueError(f"unknown variant {variant}")

out_file = f"{out_dir}/{resource}.lua"
os.makedirs(os.path.dirname(out_file), exist_ok=True)

with open(out_file, 'wb') as file:
    handle = file.fileno()
    process = Popen(['luamin', '-f', in_file], stdout=handle, stderr=DEVNULL, shell=True)
    process.wait()
