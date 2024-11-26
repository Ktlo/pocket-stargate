#!/usr/bin/env python3

import argparse
import deps
import os

args_parser = argparse.ArgumentParser(
    prog="packer",
    description="Setups development environment",
)

args_parser.add_argument('distribution')
args_parser.add_argument('destination')
args = args_parser.parse_args()

distribution = args.distribution
destination = args.destination

scope = deps.build_distribution_scope(distribution)

def mklink(resource: deps.Resource) -> None:
    filepath = f"{destination}/{resource.dev_path}"
    directory = os.path.dirname(filepath)
    if directory:
        os.makedirs(directory, exist_ok=True)
    if os.path.exists(filepath):
        os.remove(filepath)
    os.link(resource.path, filepath)

mklink(deps.base64_dependency)

for dependency in scope.dependencies:
    mklink(dependency)

for resource in scope.resources:
    mklink(resource)

for extra in scope.extras:
    mklink(extra)

mklink(scope.program)
