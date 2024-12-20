from dataclasses import dataclass
import re
import os
from typing import Optional

@dataclass
class Resource:
    path: str
    name: str
    dev_path: str

@dataclass
class Distribution:
    dependencies: list[Resource]
    resources: list[Resource]
    extras: list[Resource]
    program: Resource
    installer: Resource

dependency_pattern = re.compile("^((?P<path>.+)\\/)?(?P<dependency>[\\w\\.]+)$")

def parse_dependency(text: str) -> Resource:
    groups = dependency_pattern.search(text).groupdict()
    dependency = groups.get('dependency')
    dependency_path = dependency.replace('.', '/')
    dev_path = f"{dependency_path}.lua"
    minified_path = f"out/dependencies/{dev_path}"
    if os.path.isfile(minified_path):
        path = minified_path
    else:
        subpath = groups.get('path')
        if subpath:
            path = f"dependencies/{subpath}/{dev_path}"
        else:
            path = f"dependencies/{dev_path}"
    return Resource(path=path, name=dependency, dev_path=dev_path)

def read_dependencies(distribution: str) -> list[Resource]:
    with open(f"distributions/{distribution}/dependencies.txt") as file:
        return [parse_dependency(line.rstrip()) for line in file if line.strip() != '' and not ('base64' in line)]

def parse_resource(text: str, type: str) -> Resource:
    return Resource(path=f"{type}/{text}", name=text, dev_path=text)

def read_resources(type: str, distribution: str) -> list[Resource]:
    with open(f"distributions/{distribution}/{type}.txt") as file:
        return [parse_resource(line.rstrip(), type) for line in file if line.strip() != '']

if os.path.exists("out/dependencies/base64.lua"):
    base64_path = "out/dependencies/base64.lua"
else:
    base64_path = "dependencies/base64.lua"
base64_dependency = Resource(path=base64_path, name="base64", dev_path="base64.lua")

def build_distribution_scope(distribution: str) -> Distribution:
    dependencies = read_dependencies(distribution)
    resources = read_resources("resources", distribution)
    extras = read_resources("extras", distribution)
    minified_entrypoint = f"out/entrypoints/{distribution}.lua"
    if os.path.exists(minified_entrypoint):
        entrypoint_path = minified_entrypoint
    else:
        entrypoint_path = f"distributions/{distribution}/main.lua"
    program = Resource(entrypoint_path, f"{distribution}.lua", f"{distribution}.lua")
    minified_installer = f"out/installers/{distribution}.lua"
    if os.path.exists(minified_installer):
        installer_path = minified_installer
    else:
        installer_path = f"distributions/{distribution}/installer.lua"
    installer = Resource(installer_path, f"install_{distribution}.lua", f"install_{distribution}.lua")
    return Distribution(dependencies=dependencies, resources=resources, extras=extras, program=program, installer=installer)
