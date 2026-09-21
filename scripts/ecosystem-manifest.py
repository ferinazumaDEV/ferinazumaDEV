"""Generate or check `ecosystem.json`: one machine-readable entry point to everything this ecosystem publishes.

Why it exists. This project's whole thesis is that machine-extractability is a precondition for being cited,
and its own ecosystem was legible only by reading nine repositories one at a time. This is the manifest a
machine — an auditor's, a crawler's, anyone's — can fetch once to learn what exists, what version is published,
and where the independent evidence for each claim lives (DOI, SWHID, attestation).

Two modes, and the second is the point:
  --write  regenerate the file from live sources.
  --check  assert the committed file still matches live reality, and fail if it drifted.

A manifest nobody checks is a stale claim with a JSON extension. `--check` is what stops that: versions move,
DOIs get new versions, tags advance, and none of it touches this repository.
"""
from __future__ import annotations
import argparse, json, subprocess, sys, urllib.request, datetime, pathlib

GH = "gh"
OWNER = "ferinazumaDEV"

WORKS = [
    {"repo": "generative-engine-optimization-handbook", "kind": "work",
     "concept_doi": "10.5281/zenodo.22299644", "license": "CC-BY-SA-4.0"},
    {"repo": "generative-engine-optimization-cookbook", "kind": "work",
     "concept_doi": "10.5281/zenodo.22299279", "license": "MIT AND CC-BY-4.0"},
    {"repo": "prompt-engineering-evidence", "kind": "work",
     "concept_doi": "10.5281/zenodo.22307826", "license": "CC-BY-SA-4.0"},
]
PACKAGES = [
    {"repo": "typedout", "kind": "package", "pypi": "typedout-py", "imports": "typedout"},
    {"repo": "politeclient", "kind": "package", "pypi": "politeclient", "imports": "politeclient"},
    {"repo": "webhook-replay", "kind": "package", "pypi": "webhook-replay", "imports": "webhook_replay"},
    {"repo": "scaffld", "kind": "package", "pypi": "scaffld", "imports": "scaffld"},
    {"repo": "framesig", "kind": "package", "pypi": "framesig", "imports": "framesig"},
]

def gh_json(path):
    r = subprocess.run([GH, "api", path], capture_output=True, text=True)
    return json.loads(r.stdout) if r.returncode == 0 else None

def get_json(url, accept=None):
    h = {"User-Agent": "ferinazumaDEV-manifest/1"}
    if accept: h["Accept"] = accept
    try:
        return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=45))
    except Exception:
        return None

def latest_tag(repo):
    t = gh_json(f"repos/{OWNER}/{repo}/tags?per_page=1")
    return t[0]["name"] if t else None

def swhid_of(repo, tag):
    """SWHID of the tagged tree, as written in the release notes; read from the release body, not invented."""
    r = gh_json(f"repos/{OWNER}/{repo}/releases/tags/{tag}")
    if not r: return None
    for line in (r.get("body") or "").splitlines():
        if "swh:1:dir:" in line:
            frag = line.split("swh:1:dir:")[1]
            return "swh:1:dir:" + frag.split("`")[0].split(">")[0].split(";")[0].strip()
    return None

def build():
    out = {
        "$comment": "One machine-readable entry point to what ferinazumaDEV publishes. Regenerate with "
                    "scripts/ecosystem-manifest.py --write; the weekly workflow runs --check so it cannot rot silently.",
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "owner": OWNER,
        "items": [],
    }
    for w in WORKS:
        tag = latest_tag(w["repo"])
        rec = get_json(f"https://api.datacite.org/dois/{w['concept_doi']}")
        out["items"].append({
            "repo": f"https://github.com/{OWNER}/{w['repo']}", "kind": w["kind"], "license": w["license"],
            "latest_tag": tag, "concept_doi": w["concept_doi"],
            "doi_state": (rec or {}).get("data", {}).get("attributes", {}).get("state"),
            "swhid_dir": swhid_of(w["repo"], tag) if tag else None,
        })
    for p in PACKAGES:
        tag = latest_tag(p["repo"])
        meta = get_json(f"https://pypi.org/pypi/{p['pypi']}/json")
        ver = (meta or {}).get("info", {}).get("version")
        att = 0
        if ver:
            files = get_json(f"https://pypi.org/pypi/{p['pypi']}/{ver}/json") or {}
            for u in files.get("urls", []):
                prov = get_json(f"https://pypi.org/integrity/{p['pypi']}/{ver}/{u['filename']}/provenance",
                                accept="application/vnd.pypi.integrity.v1+json")
                att += sum(len(b.get("attestations", [])) for b in (prov or {}).get("attestation_bundles", []))
        out["items"].append({
            "repo": f"https://github.com/{OWNER}/{p['repo']}", "kind": p["kind"],
            "pypi": f"https://pypi.org/project/{p['pypi']}/", "install": p["pypi"], "imports": p["imports"],
            "latest_tag": tag, "published_version": ver, "pep740_attestations": att,
            "swhid_dir": swhid_of(p["repo"], tag) if tag else None,
        })
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--path", default="ecosystem.json")
    a = ap.parse_args()
    live = build()
    path = pathlib.Path(a.path)
    if a.write:
        path.write_text(json.dumps(live, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"written: {path} ({len(live['items'])} items)")
        return 0
    if not a.check:
        print(json.dumps(live, indent=2, ensure_ascii=False)); return 0
    if not path.exists():
        print(f"FAIL  {path} does not exist"); return 1
    committed = json.loads(path.read_text(encoding="utf-8"))
    # `generated` is expected to differ; everything else must not.
    fail = 0
    by_repo = {i["repo"]: i for i in committed.get("items", [])}
    for item in live["items"]:
        c = by_repo.get(item["repo"])
        if c is None:
            print(f"FAIL  {item['repo']} is live but missing from the manifest"); fail = 1; continue
        for k, v in item.items():
            if c.get(k) != v:
                print(f"FAIL  {item['repo']}: {k} is {v!r} live, {c.get(k)!r} in the manifest"); fail = 1
    for repo in set(by_repo) - {i["repo"] for i in live["items"]}:
        print(f"FAIL  {repo} is in the manifest but was not produced live"); fail = 1
    print("ok    the manifest matches what is published" if not fail
          else "The manifest has drifted. Regenerate it with --write and commit.")
    return fail

if __name__ == "__main__":
    sys.exit(main())
