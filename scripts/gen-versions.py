#!/usr/bin/env python3
"""用法：scripts/gen-versions.py <owner/repo>  （环境变量 GH_TOKEN 可选，用于提高 API 限额）

读取仓库的全部 Release，输出应用内更新器使用的 versions.json（标准输出）。
格式与 ErgoCore/UpdateChecker.swift 里的 VersionEntry 对应。
"""
import json
import os
import re
import sys
import urllib.request

repo = sys.argv[1]
token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")

def notes_of(body):
    """去掉开头固定的安装说明，只保留自动生成的更新日志（从 “What's Changed” 开始）。"""
    i = body.find("## What's Changed")
    return (body[i:] if i >= 0 else "").strip()[:2000]


entries = []
page = 1
while True:
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "ergo-versions"},
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        releases = json.load(resp)
    if not releases:
        break
    for r in releases:
        if r["draft"] or not re.fullmatch(r"\d+\.\d+\.\d+", r["tag_name"]):
            continue
        dmg = next((a for a in r["assets"] if a["name"].endswith(".dmg")), None)
        if not dmg:
            continue
        digest = dmg.get("digest") or ""
        sha_asset = next((a for a in r["assets"] if a["name"] == dmg["name"] + ".sha256"), None)
        entries.append({
            "version": r["tag_name"],
            "prerelease": r["prerelease"],
            "notes": notes_of(r.get("body") or ""),
            "page": r["html_url"],
            "dmg_name": dmg["name"],
            "dmg_url": dmg["browser_download_url"],
            "dmg_size": dmg["size"],
            "sha256": digest[7:].lower() if digest.startswith("sha256:") else None,
            "sha256_url": sha_asset["browser_download_url"] if sha_asset else None,
        })
    page += 1

entries.sort(key=lambda e: tuple(int(x) for x in e["version"].split(".")), reverse=True)
json.dump(entries, sys.stdout, ensure_ascii=False, indent=2)
print()
