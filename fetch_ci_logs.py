#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_ci_logs.py — Fetch GitHub Actions build-log artifacts and terminal output
for AI analysis.

For each failed CI run, downloads:
  - build-logs-<distro> artifacts (the collected my_*.log files)
  - terminal_output.log (raw stdout/stderr from the build job)

The terminal output shows the exact command lines and error messages as they
appeared in CI — read it first, then drill into individual my_*.log files.

Usage:
  python3 fetch_ci_logs.py [options]

Requires an authenticated gh CLI (gh auth login) or GITHUB_TOKEN env var.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen


REPO = "hgonomeg/coot_zerokara"
API_BASE = "https://api.github.com"


def get_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        return token
    try:
        result = subprocess.run(
            ["gh", "auth", "token"], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except FileNotFoundError:
        pass
    sys.exit("ERROR: No GitHub token. Set GITHUB_TOKEN, pass -t, or run 'gh auth login'.")


def api_get(url: str, token: str, max_pages: int = 3) -> list[dict]:
    """Fetch all items from a paginated GitHub API endpoint. Returns a flat list."""
    all_items: list[dict] = []
    collection_keys = {"workflow_runs", "artifacts", "jobs", "runners", "workflows"}

    for page in range(1, max_pages + 1):
        full_url = f"{url}?per_page=100&page={page}"
        req = Request(
            full_url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "fetch-ci-logs/1.0",
            },
        )
        try:
            with urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
        except Exception as e:
            print(f"  WARNING: API call failed for {full_url}: {e}", file=sys.stderr)
            break

        items: list[dict] = []
        if isinstance(data, list):
            items = data
        elif isinstance(data, dict):
            for key in collection_keys:
                if key in data and isinstance(data[key], list):
                    items = data[key]
                    break
            if not items:
                items = [data]
        all_items.extend(items)
        if len(items) < 100:
            break

    return all_items


def get_runs(token: str, args: argparse.Namespace) -> list[dict]:
    """Return a list of workflow run dicts matching the requested mode."""
    url = f"{API_BASE}/repos/{REPO}/actions/runs"

    if args.run:
        return api_get(f"{url}/{args.run}", token, max_pages=1)

    if args.latest:
        runs = api_get(url, token, max_pages=1)
        return runs[:1] if runs else []

    # Failed mode (default)
    print(f"  Fetching up to {args.max_runs} recent failed runs ...")
    runs = api_get(url, token, max_pages=3)
    failed = [
        r
        for r in runs
        if r.get("conclusion") in ("failure", "cancelled", "timed_out")
    ]
    return failed[: args.max_runs]


def download_artifact_via_gh(run_id: int, artifact_name: str, dest_dir: Path) -> bool:
    """Download a single artifact using `gh run download`. Returns True on success."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            [
                "gh", "run", "download", str(run_id),
                "-R", REPO,
                "-n", artifact_name,
                "-D", str(dest_dir),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        # gh prints useful info to stderr
        if e.stderr:
            print(f"    gh: {e.stderr.strip()}", file=sys.stderr)
        return False


def download_job_log(job_id: int, dest: Path) -> bool:
    """Download the terminal output for a specific job's failed steps.
    Uses `gh run view --job <id> --log-failed`, which returns only the output
    from failing steps — the first thing you want to see when triaging."""
    try:
        with open(dest, "w") as f:
            subprocess.run(
                ["gh", "run", "view", "--job", str(job_id), "--log-failed", "-R", REPO],
                check=True, stdout=f, stderr=subprocess.PIPE, text=True,
            )
        return True
    except subprocess.CalledProcessError as e:
        if e.stderr:
            print(f"    gh: {e.stderr.strip()}", file=sys.stderr)
        return False


def fetch_jobs_map(run_id: int, token: str) -> dict[str, int]:
    """Return a mapping from distro name to job ID for a run.
    The CI workflow matrix names jobs as 'build (<distro>)',
    e.g. 'build (ubuntu-24.04)' → job 123456."""
    jobs_url = f"{API_BASE}/repos/{REPO}/actions/runs/{run_id}/jobs"
    jobs = api_get(jobs_url, token, max_pages=2)

    mapping: dict[str, int] = {}
    for j in jobs:
        name = j.get("name", "")
        # Matrix job names include distro + container: "build (rocky-9, rockylinux:9)"
        # Extract just the first field (the distro name).
        if name.startswith("build (") and name.endswith(")"):
            inner = name[len("build ("):-1]
            distro = inner.split(",")[0].strip()
            mapping[distro] = j["id"]
    return mapping


def extract_artifact(archive: Path, dest: Path) -> None:
    """Extract a GitHub artifact. The artifact is a ZIP that may contain
    a build-logs.tar.zst (which we further unwrap) or .log files directly."""
    dest.mkdir(parents=True, exist_ok=True)
    print("    Extracting ...")

    if not zipfile.is_zipfile(archive):
        print(f"    WARNING: {archive} is not a ZIP — trying as tar.zst directly")
        _extract_zst(archive, dest)
        return

    with zipfile.ZipFile(archive, "r") as zf:
        tarzst_names = [n for n in zf.namelist() if n.endswith(".tar.zst")]
        if tarzst_names:
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp = Path(tmpdir)
                for name in tarzst_names:
                    zf.extract(name, path=tmp)
                    _extract_zst(tmp / name, dest)
        else:
            # No .tar.zst inside — extract everything directly
            zf.extractall(path=dest)


def _extract_zst(archive: Path, dest: Path) -> None:
    """Extract a .tar.zst archive into dest directory."""
    try:
        with tarfile.open(archive, "r:zst") as tf:
            tf.extractall(path=dest)
    except tarfile.ReadError:
        zstd = shutil.which("zstd")
        tar = shutil.which("tar")
        if not zstd or not tar:
            sys.exit(f"ERROR: Cannot extract {archive} — need Python zstd or CLI tools")
        with tempfile.NamedTemporaryFile(suffix=".tar", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        try:
            subprocess.run([zstd, "-d", "-c", str(archive)],
                           stdout=open(tmp_path, "wb"), check=True)
            subprocess.run([tar, "-xf", str(tmp_path), "-C", str(dest)], check=True)
        finally:
            tmp_path.unlink(missing_ok=True)


def match_distro(distro: str, distro_filter: list[str]) -> bool:
    if not distro_filter:
        return True
    return distro in distro_filter


def write_summary(run: dict, run_dir: Path) -> None:
    """Write SUMMARY.txt for a run directory."""
    distros = []
    if run_dir.is_dir():
        for d in sorted(run_dir.iterdir()):
            if not d.is_dir():
                continue
            has_terminal = "terminal_output.log" in [f.name for f in d.iterdir()]
            n_logs = len(list(d.rglob("*.log*")))
            tag = "  [has terminal_output.log]" if has_terminal else ""
            distros.append(f"  {d.name}  ({n_logs} log files{tag})")

    summary = f"""================================================================================
 GitHub Actions Run Summary
================================================================================

Run ID:       {run.get('id', '?')}
Title:        {run.get('display_title', '?')}
Status:       {run.get('status', '?')}
Conclusion:   {run.get('conclusion', '?')}
Branch:       {run.get('head_branch', '?')}
Created:      {run.get('created_at', '?')}
URL:          {run.get('html_url', '?')}

Distros:
{chr(10).join(distros) if distros else '  (none)'}

================================================================================
 Read terminal_output.log first (the raw build output), then drill into
 individual my_*.log files for the specific failure.
================================================================================
"""
    (run_dir / "SUMMARY.txt").write_text(summary)
    print(summary)


def _cleanup_terminal_output(path: Path) -> None:
    """Strip `gh run view --log` progress/timing annotations from the raw
    terminal output, keeping only the actual build command output."""
    lines = path.read_text().splitlines()
    cleaned = []
    for line in lines:
        # gh injects ANSI escape sequences for progress display; drop those.
        # They look like: \x1b[2K\x1b[1G  0s (etc.)
        if line.startswith("\x1b[") and len(line) < 80:
            continue
        cleaned.append(line)
    path.write_text("\n".join(cleaned) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Fetch CI build logs from GitHub Actions")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-r", "--run", type=int, help="Specific run ID")
    group.add_argument("-l", "--latest", action="store_true", help="Latest run")
    group.add_argument("-f", "--failed", action="store_true", help="Recent failed runs (default)")
    parser.add_argument("-n", "--max-runs", type=int, default=10, help="Max runs to scan")
    parser.add_argument("-o", "--output", default="./ci_logs", help="Output directory")
    parser.add_argument("-d", "--distro", action="append", default=[], help="Filter by distro (repeatable)")
    parser.add_argument("-t", "--token", help="GitHub token (or use GITHUB_TOKEN / gh auth)")
    parser.add_argument("--repo", default="hgonomeg/coot_zerokara", help="Repo (owner/name)")
    parser.add_argument("--no-terminal", action="store_true",
                        help="Skip downloading terminal output (job logs)")
    args = parser.parse_args()

    global REPO
    REPO = args.repo

    if not args.run and not args.latest:
        args.failed = True

    token = args.token or get_token()
    output_dir = Path(args.output)

    # Check gh CLI
    if not shutil.which("gh"):
        sys.exit("ERROR: 'gh' CLI not found. Install it: https://cli.github.com/")

    # --- Phase 1: find runs ---
    runs = get_runs(token, args)
    if not runs:
        sys.exit("No matching runs found.")

    print(f"  Processing {len(runs)} run(s) ...")

    # --- Phase 2: download & extract ---
    for run in runs:
        run_id = run["id"]
        conclusion = run.get("conclusion", "unknown")
        run_url = run.get("html_url", "")

        run_dir = output_dir / f"run_{run_id}_{conclusion}"
        run_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n==== Run {run_id} ({conclusion}) ====")
        print(f"     URL: {run_url}")

        # Fetch job→distro mapping so we can download the terminal output later.
        # Each matrix job is named "build (<distro>)" — we extract the distro part.
        jobs_map: dict[str, int] = {}
        if not args.no_terminal:
            try:
                jobs_map = fetch_jobs_map(run_id, token)
            except Exception as e:
                print(f"  WARNING: Could not fetch jobs: {e}", file=sys.stderr)

        # Fetch artifact metadata via API (to know what's available)
        artifacts_url = f"{API_BASE}/repos/{REPO}/actions/runs/{run_id}/artifacts"
        try:
            artifacts = api_get(artifacts_url, token, max_pages=2)
        except Exception as e:
            print(f"  WARNING: Could not fetch artifacts: {e}", file=sys.stderr)
            write_summary(run, run_dir)
            continue

        art_count = 0
        for art in artifacts:
            name = art.get("name", "")
            if not name.startswith("build-logs-"):
                continue

            distro = name.replace("build-logs-", "", 1)
            if not match_distro(distro, args.distro):
                continue

            distro_dir = run_dir / distro
            sentinel = distro_dir / ".extracted"

            if sentinel.exists():
                print(f"  {distro}: already done — skip.")
                art_count += 1
            else:
                # Download via gh CLI — handles auth + redirects correctly
                # gh run download puts the artifact contents directly into distro_dir
                print(f"  Downloading {name} ...")
                if download_artifact_via_gh(run_id, name, distro_dir):
                    # Check what we got — may be a ZIP or may be extracted already
                    downloaded_files = list(distro_dir.iterdir())
                    if len(downloaded_files) == 1 and downloaded_files[0].suffix == ".zip":
                        # gh downloaded the raw ZIP — extract it
                        extract_artifact(downloaded_files[0], distro_dir)
                        downloaded_files[0].unlink()  # remove the ZIP after extraction
                    elif len(downloaded_files) == 1 and downloaded_files[0].name.endswith(".tar.zst"):
                        # gh extracted the ZIP but left the inner .tar.zst
                        _extract_zst(downloaded_files[0], distro_dir)
                    # else: gh already extracted everything
                    sentinel.touch()
                    art_count += 1
                    print(f"  {distro}: ready")

            # --- terminal output (the raw stdout/stderr from each job) ---
            terminal_file = distro_dir / "terminal_output.log"
            if not args.no_terminal and not terminal_file.exists():
                job_id = jobs_map.get(distro)
                if job_id:
                    print(f"  {distro}: fetching terminal output ...")
                    if download_job_log(job_id, terminal_file):
                        _cleanup_terminal_output(terminal_file)
                    else:
                        print(f"    WARNING: could not download terminal output",
                              file=sys.stderr)

        write_summary(run, run_dir)
        print(f"\n  Run {run_id} ready in {run_dir}/")

    print(f"\n{'='*80}")
    print(f" Done. Logs extracted to: {output_dir}/")
    print(f"{'='*80}")


if __name__ == "__main__":
    main()
