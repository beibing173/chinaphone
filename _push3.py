#!/usr/bin/env python3
"""通过 gh api（Contents API）推送文件，绕过 git HTTPS 连接问题。"""
import base64
import json
import os
import subprocess
import sys

REPO = "beibing173/chinaphone"
GH = r"C:\Program Files\GitHub CLI\gh.exe"
ROOT = r"D:\ChinaPhone"
BRANCH = "main"

SKIP_DIRS = {".git", "dist", "reports", ".gradle", "build", ".idea", "__pycache__"}
SKIP_EXT = {".apk", ".exe", ".aab", ".dex", ".class", ".zip", ".log", ".ico", ".pyc"}
SKIP_FILES = {"_push.py", "_push2.py", "_check_yaml.py"}


def gh_api(args, input_data=None):
    cmd = [GH] + args
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True,
            encoding="utf-8", errors="replace",
            input=input_data, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if proc.returncode != 0:
        return False, (proc.stderr or proc.stdout).strip()
    out = proc.stdout.strip()
    if not out:
        return True, None
    try:
        return True, json.loads(out)
    except json.JSONDecodeError:
        return True, out


def collect_files():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn in SKIP_FILES:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            ext = os.path.splitext(fn)[1].lower()
            if ext in SKIP_EXT:
                continue
            with open(full, "rb") as f:
                raw = f.read()
            try:
                raw.decode("utf-8")
            except UnicodeDecodeError:
                print(f"  skip binary: {rel}")
                continue
            files.append((rel, raw))
    return sorted(files, key=lambda x: x[0])


def remote_sha(rel):
    ok, info = gh_api(["api", f"repos/{REPO}/contents/{rel}?ref={BRANCH}"])
    if ok and isinstance(info, dict) and info.get("sha"):
        return info["sha"]
    return None


def main():
    files = collect_files()
    print(f"待处理: {len(files)} 个文件\n")
    ok_count, skip_count, fail = 0, 0, []

    for i, (rel, raw) in enumerate(files, 1):
        content_b64 = base64.b64encode(raw).decode()
        existing = remote_sha(rel)

        payload = {
            "message": ("update: " if existing else "add: ") + rel,
            "content": content_b64,
            "branch": BRANCH,
        }
        if existing:
            payload["sha"] = existing

        ok, resp = gh_api(
            ["api", f"repos/{REPO}/contents/{rel}", "-X", "PUT", "--input", "-"],
            input_data=json.dumps(payload),
        )
        if ok:
            ok_count += 1
            mark = "UPD" if existing else "NEW"
            print(f"  [{i}/{len(files)}] {mark}  {rel}")
        else:
            fail.append((rel, str(resp)[:160]))
            print(f"  [{i}/{len(files)}] FAIL {rel}  {str(resp)[:120]}")

    print(f"\n成功 {ok_count} / {len(files)}  失败 {len(fail)}")
    if fail:
        for rel, err in fail[:15]:
            print(f"  - {rel}: {err}")
        sys.exit(1)
    print(f"\nhttps://github.com/{REPO}")


if __name__ == "__main__":
    main()
