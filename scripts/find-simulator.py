#!/usr/bin/env python3
"""Prints "<udid>\t<name>" of the available iOS simulator with this name or id.

Usage: scripts/find-simulator.py <name or udid> [--create]

It takes the one under the newest iOS that has it. It never downloads a runtime. With --create
(on GitHub's runners only: AGENTS.md keeps our Macs to the simulators already installed), a
simulator that isn't there is made on the newest installed iOS runtime that supports its kind.
"""
import json
import subprocess
import sys


def simctl(*args):
    output = subprocess.run(["xcrun", "simctl", "list", *args, "-j"], check=True, capture_output=True, text=True).stdout
    return json.loads(output)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    wanted, create = sys.argv[1], "--create" in sys.argv[2:]
    runtimes = [r for r in simctl("runtimes", "available")["runtimes"] if r.get("platform") == "iOS"]
    version = {r["identifier"]: tuple(int(part) for part in r["version"].split(".")) for r in runtimes}
    found = sorted(
        ((version[runtime], device) for runtime, devices in simctl("devices", "available")["devices"].items()
         if runtime in version for device in devices if wanted in (device["udid"], device["name"])),
        key=lambda pair: pair[0],
    )
    if found:
        device = found[-1][1]
        print(f"{device['udid']}\t{device['name']}")
        return
    if not create:
        sys.exit(f"No simulator named {wanted} is installed. Pick one from `xcrun simctl list devices available`.")
    kind = next((t for t in simctl("devicetypes")["devicetypes"] if t["name"] == wanted), None)
    supporting = [r for r in runtimes if kind and any(t["identifier"] == kind["identifier"] for t in r.get("supportedDeviceTypes", []))]
    if not supporting:
        sys.exit(f"No installed iOS runtime runs a {wanted}.")
    runtime = max(supporting, key=lambda r: version[r["identifier"]])
    udid = subprocess.run(["xcrun", "simctl", "create", wanted, kind["identifier"], runtime["identifier"]],
                          check=True, capture_output=True, text=True).stdout.strip()
    print(f"{udid}\t{wanted}")


if __name__ == "__main__":
    main()
