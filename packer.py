#!/usr/bin/env python3

import argparse
import base64
import deps
import os

args_parser = argparse.ArgumentParser(
    prog="packer",
    description="Packs a lua program to a single file",
)

args_parser.add_argument('distribution')
args = args_parser.parse_args()

try:
    os.mkdir("out")
except:
    pass

distribution = args.distribution

scope = deps.build_distribution_scope(distribution)

def load_resource(resource: deps.Resource) -> bytes:
    with open(resource.path, 'rb') as file:
        return file.read()

def encode_text(text: bytes):
    encoded = base64.b64encode(text)
    return encoded.decode('utf-8')

loader_text = """
local function loader(module)
    if module == 'base64' then
        return function() return base64 end
    else
        local text = modules[module]
        if not text then
            return nil, "not embedded in program"
        end
        modules[module] = nil
        return load(text, module..".lua", 't', _ENV)
    end
end
table.insert(package.loaders, loader)
"""

def base64header(file):
    file.write("local base64 = [[")
    base64_lua = load_resource(deps.base64_dependency).decode('utf-8')
    file.write(base64_lua)
    file.write("]]\nbase64 = load(base64, \"base64.lua\", 't', _ENV)()\n")

def include_resources(file, resources):
    for resource in resources:
        file.write("    [\"")
        file.write(resource.name)
        file.write("\"] = base64.decode \"")
        resource_text = load_resource(resource)
        encoded_resource = encode_text(resource_text)
        file.write(encoded_resource)
        file.write("\";\n")

with open(f"out/{distribution}.lua", 'w', newline='') as file:
    base64header(file)
    file.write("local modules = {\n")
    for dependency in scope.dependencies:
        file.write("    [\"")
        file.write(dependency.name)
        file.write("\"] = base64.decode \"")
        dependency_text = load_resource(dependency)
        encoded_dependency = encode_text(dependency_text)
        file.write(encoded_dependency)
        file.write("\";\n")
    file.write('}')
    file.write(loader_text)
    file.write("_G.RESOURCES = {\n")
    include_resources(file, scope.resources)
    file.write("}\n")
    file.write("local entrypoint = \"")
    file.write(encode_text(load_resource(scope.program)))
    file.write("\"\n")
    file.write(f"return load(base64.decode(entrypoint), \"{distribution}.lua\", 't', _ENV)(...)\n")

installer_functions_text = f"""
function saveExtra(resource, filename)
    filename = filename or resource
    local file = assert(io.open(filename, 'w'))
    file:write(EXTRAS[resource])
    file:close()
end
function saveProgram(filename)
    filename = filename or "{distribution}.lua"
    local file = assert(io.open(filename, 'w'))
    file:write(PROGRAM)
    file:close()
end
function typeY()
    write("Do you want to continue? (Type Y for continue): ")
    local read = read(nil, nil, nil, "N")
    if read ~= 'Y' then
        print("Exiting...")
        error("Terminated", 0)
    end
end
"""

with open(f"out/install_{distribution}.lua", 'w', newline='') as file:
    base64header(file)
    file.write(installer_functions_text)
    file.write("EXTRAS = {\n")
    include_resources(file, scope.extras)
    file.write("}\n")
    file.write("PROGRAM = ([[")
    dependency_text = load_resource(deps.Resource(f"out/{distribution}.lua", distribution, f"{distribution}.lua"))
    file.write(dependency_text.decode('utf-8').replace("[[", "<$<").replace("]]", ">$>"))
    file.write("]]):gsub(\"<$<\", \"[[\"):gsub(\">$>\", \"]]\")\n")
    file.write("local entrypoint = base64.decode \"")
    file.write(encode_text(load_resource(scope.installer)))
    file.write("\"\n")
    file.write("return load(entrypoint, \"installer.lua\", 't', _ENV)(...)\n")
