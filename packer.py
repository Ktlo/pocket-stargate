#!/usr/bin/env python3

import dataclasses
import argparse
import base64
import re
import os

args_parser = argparse.ArgumentParser(
    prog="packer",
    description="Packs a lua program to a single file",
)

args_parser.add_argument('distribution')
args_parser.add_argument('branch')
args = args_parser.parse_args()

try:
    os.mkdir("out")
except:
    pass

distribution = args.distribution
branch = args.branch

@dataclasses.dataclass
class Dependency:
    path: str
    name: str

dependency_pattern = re.compile("^((?P<path>.+)\\/)?(?P<dependency>[\\w\\.]+)$")

def parse_dependency(text):
    groups = dependency_pattern.search(text).groupdict()
    dependency = groups.get('dependency')
    subpath = groups.get('path')
    dependency_path = dependency.replace('.', '/')
    if subpath:
        path = f"dependencies/{subpath}/{dependency_path}.lua"
    else:
        path = f"dependencies/{dependency_path}.lua"
    return Dependency(path=path, name=dependency)

def read_dependencies():
    with open(f"distributions/{distribution}/dependencies.txt") as file:
        return [parse_dependency(line.rstrip()) for line in file if line.strip() != '' and not ('base64' in line)]

dependencies = read_dependencies()

base64_dependency = Dependency(path="dependencies/base64.lua", name="base64")

def parse_resource(text):
    return Dependency(path=f"resources/{text}", name=text)

def read_resources():
    with open(f"distributions/{distribution}/resources.txt") as file:
        return [parse_resource(line.rstrip()) for line in file if line.strip() != '']

resources = read_resources()

def load_entrypoint():
    with open(f"distributions/{distribution}/main.lua", 'rb') as file:
        return file.read()

def load_dependency(dependency: Dependency):
    with open(dependency.path, 'rb') as file:
        return file.read()

def encode_text(text: bytes):
    encoded = base64.b64encode(text)
    return encoded.decode('utf-8')

loader_text = """
local function load_module(module, text)
    return load(text, module..".lua", 't', _ENV)
end
local function loader(module)
    if module == 'base64' then
        return function() return base64 end
    else
        local text = modules[module]
        if not text then
            return nil
        end
        modules[module] = nil
        return load_module(module, base64.decode(text))
    end
end
table.insert(package.loaders, loader)
"""

with open(f"out/{distribution}.lua", 'w') as file:
    file.write("local base64 = [[")
    base64_lua = load_dependency(base64_dependency).decode('utf-8')
    file.write(base64_lua)
    file.write("]]\n")
    file.write("local modules = {\n")
    for dependency in dependencies:
        file.write("    [\"")
        file.write(dependency.name)
        file.write("\"] = '")
        dependency_text = load_dependency(dependency)
        encoded_dependency = encode_text(dependency_text)
        file.write(encoded_dependency)
        file.write("';\n")
    file.write('}')
    file.write(loader_text)
    file.write("base64 = load_module('base64', base64)()\n")
    file.write("_G.RESOURCES = {\n")
    for resource in resources:
        file.write("    [\"")
        file.write(resource.name)
        file.write("\"] = base64.decode '")
        resource_text = load_dependency(resource)
        encoded_resource = encode_text(resource_text)
        file.write(encoded_resource)
        file.write("';\n")
    file.write('}')
    file.write("local entrypoint = '")
    file.write(encode_text(load_entrypoint()))
    file.write("'\n")
    file.write(f"entrypoint = load_module('{distribution}', base64.decode(entrypoint))\n")
    file.write('return entrypoint(...)\n')

with open(f"out/install_{distribution}.lua", 'wb') as output:
    output.write(bytes(f"local BRANCH = '{branch}'\n", 'utf-8'))
    with open(f"distributions/{distribution}/installer.lua", 'rb') as input:
        output.write(input.read())
