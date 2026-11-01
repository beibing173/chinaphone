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
SKIP_FILES = {"_push.py", "_check_yaml.py"}


def gh_api(args, input_data=None):
    """调用 gh api，返回 (ok, parsed_json_or_text)"""
    cmd = [GH] + args
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            input=input_data,
            timeout=120,
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
                print(f"  跳过二进制: {rel}")
                continue
            files.append((rel, raw))
    return sorted(files, key=lambda x: x[0])


def main():
    files = collect_files()
    print(f"待上传: {len(files)} 个文件\n")

    # 先把 .gitignore 和一个占位文件提交，让仓库非空
    first = True
    ok_count = 0
    fail = []

    for i, (rel, raw) in enumerate(files, 1):
        content_b64 = base64.b64encode(raw).decode()
        payload = json.dumps({
            "message": f"add: {rel}",
            "content": content_b64,
            "branch": BRANCH,
        })
        args = [
            "api", f"repos/{REPO}/contents/{rel}",
            "-X", "PUT",
            "--input", "-",
        ]
        ok, resp = gh_api(args, input_data=payload)
        if ok:
            ok_count += 1
            print(f"  [{i}/{len(files)}] OK  {rel}")
            first = False
        else:
            # 文件已存在则用 sha 更新
            if "sha" in str(resp).lower() or "422" in str(resp):
                ok2, info = gh_api(["api", f"repos/{REPO}/contents/{rel}?ref={BRANCH}"])
                if ok2 and isinstance(info, dict) and info.get("sha"):
                    payload2 = json.dumps({
                        "message": f"update: {rel}",
                        "content": content_b64,
                        "sha": info["sha"],
                        "branch": BRANCH,
                    })
                    ok3, resp3 = gh_api([
                        "api", f"repos/{REPO}/contents/{rel}",
                        "-X", "PUT", "--input", "-",
                    ], input_data=payload2)
                    if ok3:
                        ok_count += 1
                        print(f"  [{i}/{len(files)}] OK* {rel}")
                        continue
            fail.append((rel, str(resp)[:200]))
            print(f"  [{i}/{len(files)}] FAIL {rel}")
            print(f"        {str(resp)[:200]}")

    print(f"\n成功 {ok_count} / {len(files)}")
    if fail:
        print(f"失败 {len(fail)}:")
        for rel, err in fail[:10]:
            print(f"  - {rel}: {err}")
        sys.exit(1)

    print(f"\n完成: https://github.com/{REPO}")


if __name__ == "__main__":
    main()
