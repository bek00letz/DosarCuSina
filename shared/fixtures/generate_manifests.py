#!/usr/bin/env python3
"""Regenerates manifest.json (and the v2 attachment metadata) for the golden
.dosar fixtures after their data files change.

Usage: python3 shared/fixtures/generate_manifests.py
"""
import hashlib, json, os

ROOT = os.path.dirname(os.path.abspath(__file__))


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def files_under(base):
    result = []
    for folder, _, names in os.walk(base):
        for name in sorted(names):
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, base).replace(os.sep, "/")
            if rel != "manifest.json":
                result.append(rel)
    return sorted(result)


def write_json(path, value):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def v3(base):
    attachments_path = os.path.join(base, "data/attachments.json")
    attachments = json.load(open(attachments_path, encoding="utf-8"))
    for item in attachments:
        paths = ([item["path"]] if item.get("path") else []) + item.get("pagePaths", [])
        item["byteCount"] = sum(os.path.getsize(os.path.join(base, p)) for p in paths)
        if item.get("path"):
            item["sha256"] = sha(os.path.join(base, item["path"]))
    write_json(attachments_path, attachments)

    def count(name):
        path = os.path.join(base, "data", name)
        return len(json.load(open(path, encoding="utf-8"))) if os.path.exists(path) else 0

    manifest = {
        "format": "com.ar.dosarcusina.dossier",
        "schemaVersion": 3,
        "appVersion": "1.0",
        "platform": "iOS",
        "exportedAt": "2026-03-02T08:00:00Z",
        "counts": {
            "templates": count("templates.json"),
            "assets": count("assets.json"),
            "obligations": count("obligations.json"),
            "historyEntries": count("history.json"),
            "serviceItems": count("service_items.json"),
            "providers": count("providers.json"),
            "measurements": count("measurements.json"),
            "attachments": count("attachments.json"),
        },
        "checksums": {rel: sha(os.path.join(base, rel)) for rel in files_under(base)},
    }
    write_json(os.path.join(base, "manifest.json"), manifest)


def v2(base):
    vault = os.path.join(base, "vault")
    meta = []
    for name in sorted(os.listdir(vault)):
        stem, ext = os.path.splitext(name)
        path = os.path.join(vault, name)
        meta.append({
            "id": stem,
            "assetId": "B1B2C3D4-0000-4000-8000-000000000002",
            "eventId": "E1B2C3D4-0000-4000-8000-000000000005",
            "fileName": "raport-itp" + ext,
            "fileExtension": ext.lstrip("."),
            "fileSizeBytes": os.path.getsize(path),
            "createdAt": "2025-08-20T10:05:00Z",
            "vaultRelativePath": "vault/" + name,
            "sha256": sha(path),
        })
    write_json(os.path.join(base, "data/attachments_meta.json"), meta)

    def count(name):
        path = os.path.join(base, "data", name)
        return len(json.load(open(path, encoding="utf-8"))) if os.path.exists(path) else 0

    manifest = {
        "schemaVersion": 2,
        "appVersion": "2.0.0",
        "appName": "Dosar cu Șină",
        "exportDate": "2025-10-02T08:00:00Z",
        "platform": "iOS",
        "deviceId": "00000000-0000-0000-0000-000000000000",
        "format": "com.ar.dosarcusina.dossier",
        "entityCounts": {
            "assets": count("assets.json"),
            "events": count("events.json"),
            "serviceItems": count("service_history.json"),
            "measurements": count("measurements.json"),
            "dynamicFields": 1,
            "attachments": len(meta),
        },
        "checksums": {rel: sha(os.path.join(base, rel)) for rel in files_under(base)},
    }
    write_json(os.path.join(base, "manifest.json"), manifest)


v3(os.path.join(ROOT, "dosar-v3", "household"))
v2(os.path.join(ROOT, "dosar-v2", "ios-export"))
print("manifests written")
