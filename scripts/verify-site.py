#!/usr/bin/env python3
"""Validate the dependency-free Pages payload and strict updater manifest."""

from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
SHA256 = re.compile(r"^[0-9a-f]{64}$")
VERSION = re.compile(r'^\s*version:\s*"(?P<version>\d+\.\d+\.\d+)",\s*$', re.MULTILINE)


class ResourceParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.resources: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag in {"img", "script"} and values.get("src"):
            self.resources.append(values["src"] or "")
        if tag == "link" and values.get("href"):
            self.resources.append(values["href"] or "")


def fail(message: str) -> None:
    raise AssertionError(message)


def validate_manifest() -> str:
    manifest_path = ROOT / "update.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if set(manifest) != {"schema", "version", "channel", "assets"}:
        fail("update.json has unknown or missing root fields")
    if manifest["schema"] != 1 or manifest["channel"] != "stable":
        fail("update.json schema/channel is invalid")
    if set(manifest["assets"]) != {"subsdk4", "main_npdm"}:
        fail("update.json must contain exactly subsdk4 and main_npdm")
    for name, asset in manifest["assets"].items():
        if set(asset) != {"url", "sha256", "size"}:
            fail(f"{name} has unknown or missing fields")
        parsed = urlparse(asset["url"])
        if parsed.scheme != "https" or parsed.netloc != "github.com":
            fail(f"{name} URL is not a GitHub HTTPS URL")
        if not SHA256.fullmatch(asset["sha256"]):
            fail(f"{name} SHA-256 is invalid")
        if not isinstance(asset["size"], int) or asset["size"] <= 0:
            fail(f"{name} size is invalid")
    return manifest["version"]


def validate_site(version: str) -> None:
    required = {
        "index.html",
        ".nojekyll",
        "assets/styles.css",
        "assets/site-data.js",
        "assets/site.js",
        "assets/TaneClient_logo.png",
    }
    missing = sorted(path for path in required if not (ROOT / path).is_file())
    if missing:
        fail(f"missing site files: {', '.join(missing)}")

    html = (ROOT / "index.html").read_text(encoding="utf-8")
    parser = ResourceParser()
    parser.feed(html)
    for resource in parser.resources:
        parsed = urlparse(resource)
        if parsed.scheme or parsed.netloc:
            fail(f"external UI dependency is not allowed: {resource}")
        if resource.startswith("/"):
            fail(f"project-site resource uses a domain-root path: {resource}")
        if not (ROOT / parsed.path).is_file():
            fail(f"missing referenced resource: {resource}")

    site_data = (ROOT / "assets/site-data.js").read_text(encoding="utf-8")
    version_match = VERSION.search(site_data)
    if not version_match or version_match.group("version") != version:
        fail("site display version does not match update.json")
    expected_zip = f"TaneClientNSE-v{version}.zip"
    if expected_zip not in site_data:
        fail("site release data does not reference the current ZIP")

    served_text = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in ("index.html", "assets/styles.css", "assets/site-data.js", "assets/site.js")
    ).lower()
    forbidden = ("google-analytics", "googletagmanager", "tracking pixel", "ida pro", "hook address")
    for token in forbidden:
        if token in served_text:
            fail(f"forbidden public-site content found: {token}")


def main() -> int:
    try:
        version = validate_manifest()
        validate_site(version)
    except (AssertionError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Site verification FAILED: {error}", file=sys.stderr)
        return 1
    print(f"Site verification PASS: stable v{version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
