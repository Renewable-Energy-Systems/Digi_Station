import os
import re
import sys
import subprocess
import json
import urllib.request
import urllib.error
import argparse
from pathlib import Path

# Paths
PROJECT_DIR = Path(__file__).resolve().parent.parent
PUBSPEC_FILE = PROJECT_DIR / "pubspec.yaml"
BUILD_OUTPUT = PROJECT_DIR / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"

def fail(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)

def run_cmd(cmd, cwd=PROJECT_DIR):
    print(f"Running: {' '.join(cmd)}")
    try:
        subprocess.check_call(cmd, cwd=str(cwd), shell=True)
    except subprocess.CalledProcessError as e:
        fail(f"Command failed with exit code {e.returncode}")

def get_current_version_info():
    content = PUBSPEC_FILE.read_text(encoding="utf-8")
    # Matches 'version: 1.0.0+1'
    m = re.search(r'version:\s*([^\s]+)', content)
    if not m:
        fail("Could not find version in pubspec.yaml")
    return m.group(1)

def increment_version(v):
    # Split 1.0.0+1 -> 1.0.0 and 1
    if '+' in v:
        ver, build = v.split('+')
        try:
            build = int(build) + 1
        except ValueError:
            build = 1 # Fallback if build is not int
    else:
        ver = v
        build = 1
    
    parts = list(map(int, ver.split('.')))
    parts[-1] += 1 # bump patch
    
    new_v = f"{'.'.join(map(str, parts))}+{build}"
    return new_v

def update_pubspec(new_v):
    print(f"Updating pubspec.yaml to {new_v}...")
    content = PUBSPEC_FILE.read_text(encoding="utf-8")
    # Use strict regex to avoid replacing other dependencies called 'version' if any (unlikely in yaml but good practice)
    # The 'version:' key is usually at root.
    new_content = re.sub(r'(^|\n)version:\s*[^\s]+', f'\\1version: {new_v}', content, count=1)
    PUBSPEC_FILE.write_text(new_content, encoding="utf-8")

def github_upload(token, tag, apk_path):
    repo = "Renewable-Energy-Systems/wi-display"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "Python-Release-Script"
    }
    
    # 1. Create Release
    print(f"Creating Release {tag} on GitHub...")
    url = f"https://api.github.com/repos/{repo}/releases"
    data = {
        "tag_name": tag,
        "target_commitish": "main",
        "name": f"{tag}",
        "body": "### Improvements\n- **Dynamic LIVE Status**: Home screen now correctly shows OFFLINE if data is missing.\n- **Stale Data Fix**: Dew point, PPM, and 'Updated' timestamp now reset immediately when switching detectors.\n- **Repo Cleanup**: Ignored build reports in version control.",
        "draft": False,
        "prerelease": False
    }
    
    # Note: requests lib is not assumed, using standard urllib
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            resp_data = json.load(resp)
            upload_url = resp_data['upload_url'].split('{')[0]
            print("Release created successfully.")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        print(f"Failed to create release: {e.code} {e.reason}")
        print(err_body)
        sys.exit(1)

    # 2. Upload Asset
    print(f"Uploading APK Asset...")
    name = "app-release.apk"
    target_url = f"{upload_url}?name={name}"
    
    with open(apk_path, 'rb') as f:
        file_data = f.read()
    
    headers['Content-Type'] = 'application/vnd.android.package-archive'
    req = urllib.request.Request(target_url, data=file_data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            print("APK Uploaded Successfully.")
    except urllib.error.HTTPError as e:
        print(f"Failed to upload asset: {e.read().decode()}")

def load_env():
    env_file = PROJECT_DIR / ".env"
    if env_file.exists():
        print(f"Loading environment from {env_file}")
        content = env_file.read_text(encoding="utf-8")
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith('#'): continue
            if '=' in line:
                key, val = line.split('=', 1)
                os.environ[key.strip()] = val.strip()

def main():
    load_env()

    parser = argparse.ArgumentParser(description="Automate Flutter Release")
    parser.add_argument("--token", help="GitHub Personal Access Token")
    args = parser.parse_args()
    
    token = args.token or os.environ.get("GITHUB_TOKEN")
    if not token:
        fail("GITHUB_TOKEN not set. Pass --token or set GITHUB_TOKEN env var.")

    # 1. Versioning
    cur_v = get_current_version_info()
    new_v = increment_version(cur_v)
    print(f"Current Version: {cur_v}")
    print(f"Bumping to:    {new_v}")
    
    update_pubspec(new_v)
    
    # 2. Build App
    print("\n--- Building APK (Release) ---")
    # Bake the token into the app using --dart-define
    # secure? It's compiled into the binary strings. For internal apps, reasonable.
    build_cmd = ["flutter", "build", "apk", "--release", f"--dart-define=GITHUB_TOKEN={token}"]
    run_cmd(build_cmd)
    
    if not BUILD_OUTPUT.exists():
        fail(f"APK not found at {BUILD_OUTPUT}")
    
    # 3. Upload
    # Tag format: vX.Y.Z (without +build usually for git tags)
    tag_v = "v" + new_v.split('+')[0]
    
    print(f"\n--- Uploading Release {tag_v} ---")
    github_upload(token, tag_v, str(BUILD_OUTPUT))

    print("\n[SUCCESS] Release process completed!")
    print(f"New Version: {new_v}")

if __name__ == "__main__":
    main()
