#!/usr/bin/env bash
# Every published package still verifies the way RELEASING.md tells a stranger to verify it.
#
# Why this exists: documenting a verification procedure is not the same as the procedure still working.
# On 2026-09-21 the five packages were checked by hand, end to end, and all five passed — including the two
# whose GitHub Release was assembled by hand after a workflow failed. This turns that one-off proof into a
# standing one. Read-only: it downloads from PyPI and reads GitHub; it never writes anything.
#
# The chain, per package, in the order a stranger would walk it:
#   1. PyPI serves bytes whose sha256 matches what PyPI itself declares.
#   2. Those same hashes appear in the SHA256SUMS asset of the matching GitHub Release.
#   3. The build attestation verifies against the owning repository.
#   4. PyPI's Integrity API carries a PEP 740 attestation naming that repository as publisher.
#      (The `provenance` key of the PyPI JSON API is null for everyone; it is not evidence.)
#
# Honesty rule, deliberate: "could not check" is a FAILURE, never a pass. A guard whose empty case looks
# like its success case is decoration. Every step either proves something or fails loudly.
set -uo pipefail

PACKAGES=(
  "typedout-py:typedout"
  "politeclient:politeclient"
  "webhook-replay:webhook-replay"
  "scaffld:scaffld"
  "framesig:framesig"
)

fail=0
bad() { echo "FAIL  $*"; fail=1; }
ok()  { echo "ok    $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { bad "missing tool: $1"; exit 1; }; }
need curl; need python3; need gh; need sha256sum

for entry in "${PACKAGES[@]}"; do
  pkg="${entry%%:*}"; repo="${entry##*:}"
  echo "--- $pkg (ferinazumaDEV/$repo)"

  meta=$(curl -sS --max-time 40 "https://pypi.org/pypi/$pkg/json") || { bad "$pkg: PyPI unreachable"; continue; }
  ver=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null)
  [ -n "$ver" ] || { bad "$pkg: could not read the published version from PyPI"; continue; }

  d=$(mktemp -d)
  # The JSON goes to a FILE, not through a pipe: the python program arrives on stdin via heredoc, which
  # already occupies it. Piping the JSON in as well silently gives python an empty stdin.
  curl -sS --max-time 40 -o "$d/release.json" "https://pypi.org/pypi/$pkg/$ver/json" \
    || { bad "$pkg $ver: PyPI unreachable"; rm -rf "$d"; continue; }

  # 1) bytes from PyPI match PyPI's own digests
  if ! python3 - "$d/release.json" "$d" <<'PY'
import json,sys,urllib.request,hashlib,os
d=json.load(open(sys.argv[1])); dest=sys.argv[2]; bad=0
for u in d["urls"]:
    b=urllib.request.urlopen(u["url"],timeout=90).read()
    open(os.path.join(dest,u["filename"]),"wb").write(b)
    if hashlib.sha256(b).hexdigest()!=u["digests"]["sha256"]:
        print("digest mismatch:",u["filename"]); bad=1
sys.exit(bad)
PY
  then bad "$pkg $ver: bytes served by PyPI do not match PyPI's own sha256"; rm -rf "$d"; continue
  else ok "$pkg $ver: PyPI bytes match PyPI digests"; fi

  # 2) the same hashes are the ones the GitHub Release published
  if gh release download "v$ver" -R "ferinazumaDEV/$repo" -p "SHA256SUMS" -D "$d" --clobber >/dev/null 2>&1 \
     && [ -s "$d/SHA256SUMS" ]; then
    if ( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
      ok "$pkg $ver: matches SHA256SUMS of release v$ver"
    else
      bad "$pkg $ver: PyPI bytes DIFFER from the release's SHA256SUMS"
    fi
  else
    bad "$pkg $ver: no readable SHA256SUMS on release v$ver (cannot check, so this fails)"
  fi

  # 3) build attestation
  for f in "$d"/*.whl "$d"/*.tar.gz; do
    [ -e "$f" ] || continue
    if gh attestation verify "$f" --repo "ferinazumaDEV/$repo" >/dev/null 2>&1; then
      ok "$pkg $ver: build attestation valid for $(basename "$f")"
    else
      bad "$pkg $ver: build attestation did NOT verify for $(basename "$f")"
    fi
  done

  # 4) PEP 740 provenance in the Integrity API, with the right publisher
  if ! python3 - "$d/release.json" "$pkg" "$ver" "$repo" <<'PY'
import json,sys,urllib.request
d=json.load(open(sys.argv[1])); pkg,ver,repo=sys.argv[2],sys.argv[3],sys.argv[4]; bad=0
for u in d["urls"]:
    req=urllib.request.Request(
        f"https://pypi.org/integrity/{pkg}/{ver}/{u['filename']}/provenance",
        headers={"Accept":"application/vnd.pypi.integrity.v1+json"})
    try:
        j=json.load(urllib.request.urlopen(req,timeout=60))
    except Exception as e:
        print("no provenance for",u["filename"],type(e).__name__); bad=1; continue
    bundles=j.get("attestation_bundles",[])
    n=sum(len(b.get("attestations",[])) for b in bundles)
    pubs={b.get("publisher",{}).get("repository") for b in bundles}
    if n<1: print("zero attestations for",u["filename"]); bad=1
    if f"ferinazumaDEV/{repo}" not in pubs: print("wrong publisher for",u["filename"],pubs); bad=1
sys.exit(bad)
PY
  then bad "$pkg $ver: PEP 740 provenance missing or from the wrong publisher"
  else ok "$pkg $ver: PEP 740 provenance present, publisher ferinazumaDEV/$repo"; fi

  rm -rf "$d"
done

echo
if [ "$fail" -eq 0 ]; then
  echo "All published packages verify end to end."
else
  echo "At least one link in the chain is broken. Read the FAIL lines above."
fi
exit "$fail"
