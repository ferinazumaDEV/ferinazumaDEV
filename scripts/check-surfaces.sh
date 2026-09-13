#!/usr/bin/env bash
# The public surfaces of ferinazumaDEV say the same thing: same handle, same links, no retired
# promise. Read-only. Exit 1 on the first disagreement, listing every one found.
#
# Patterns follow what the surfaces actually pre-render (measured 2026-09-13): the Contra profile
# HTML pre-renders 4 of the 5 works, so per-work links are checked on each work's own page, and
# the profile is only asserted for what must NOT be there plus the two identity anchors.
set -uo pipefail
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128 Safari/537.36'
fetch() { curl -sL -A "$UA" --max-time 40 --retry 2 --retry-delay 5 "$1"; }
fail=0
bad() { echo "FAIL  $*"; fail=1; }
ok()  { echo "ok    $*"; }

# --- Contra: profile ------------------------------------------------------------------------
profile=$(fetch https://contra.com/fernando_aporta_franco_17sinasg)
[ "${#profile}" -gt 20000 ] || bad "contra profile: only ${#profile} bytes fetched (blocked or down)"
for p in 'github\.com/ferinazuma[^D]' 'structllm' 'any LLM' 'provider-agnostic' 'Automation Engineer' 'cal\.com/ferinazumadev'; do
  n=$(printf '%s' "$profile" | grep -oE "$p" | wc -l)
  [ "$n" -eq 0 ] && ok "contra profile: '$p' absent" || bad "contra profile: '$p' present ($n)"
done
for p in 'ferinazumaDEV' 'zentimes\.es' 'linkedin\.com/in/fernando-aporta-franco-340219230'; do
  n=$(printf '%s' "$profile" | grep -oE "$p" | wc -l)
  [ "$n" -ge 1 ] && ok "contra profile: '$p' present ($n)" || bad "contra profile: '$p' missing"
done

# --- Contra: each work links its repository -------------------------------------------------
declare -A WORK=(
  [typedout]=NAgB3B7g-typedout-schema-validated-json-from-open-ai-and-anthropic
  [scaffld]=2ZclUXEN-scaffld-a-tui-that-scaffolds-ready-to-run-python-projects
  [framesig]=NgeQRmWo-framesig-on-screen-events-in-video-found-by-pixel-signature
  [politeclient]=v2Oemgo7-politeclient-a-well-behaved-http-client-for-python
  [webhook-replay]=OUorF3OP-webhook-replay-capture-a-webhook-once-replay-it-locally
)
for repo in "${!WORK[@]}"; do
  page=$(fetch "https://contra.com/p/${WORK[$repo]}")
  if printf '%s' "$page" | grep -qE "github\.com/ferinazumaDEV/$repo"; then ok "contra work $repo links github.com/ferinazumaDEV/$repo"
  else bad "contra work $repo: no link to github.com/ferinazumaDEV/$repo (page ${#page} bytes)"; fi
  printf '%s' "$page" | grep -qiE 'any LLM|provider-agnostic|bulletproof' && bad "contra work $repo: retired promise present"
done

# --- GitHub profile ---------------------------------------------------------------------------
u=$(curl -sS --max-time 30 -H 'Accept: application/vnd.github+json' https://api.github.com/users/ferinazumaDEV)
[ "$(printf '%s' "$u" | jq -r .blog)" = "https://zentimes.es" ] && ok "github profile: blog = zentimes.es" || bad "github profile: blog is $(printf '%s' "$u" | jq -r .blog)"
[ "$(printf '%s' "$u" | jq -r .name)" = "Fernando Aporta Franco" ] && ok "github profile: name" || bad "github profile: name is $(printf '%s' "$u" | jq -r .name)"
printf '%s' "$u" | jq -r '.bio // ""' | grep -qiE 'any LLM|provider-agnostic|automation engineer' && bad "github profile: retired wording in bio"
sa=$(curl -sS --max-time 30 https://api.github.com/users/ferinazumaDEV/social_accounts | jq -r '.[].url' 2>/dev/null)
for want in linkedin.com/in/fernando-aporta-franco-340219230 contra.com/fernando_aporta_franco_17sinasg; do
  printf '%s' "$sa" | grep -q "$want" && ok "github social accounts: $want" || bad "github social accounts: $want missing"
done

# --- zentimes.es --------------------------------------------------------------------------------
z=$(fetch https://zentimes.es/)
printf '%s' "$z" | grep -q 'ferinazumaDEV' && ok "zentimes.es links the handle" || bad "zentimes.es: handle missing"
printf '%s' "$z" | grep -qiE 'any LLM|provider-agnostic|structllm' && bad "zentimes.es: retired wording present"
code=$(curl -s -o /dev/null -A "$UA" --max-time 30 -w '%{http_code}' https://zentimes.es/llms.txt)
[ "$code" = "200" ] && ok "zentimes.es/llms.txt 200" || bad "zentimes.es/llms.txt -> $code"

# --- PyPI: the five packages exist and each says where it comes from ---------------------------
for pkg in typedout-py scaffld framesig politeclient webhook-replay; do
  j=$(curl -sS --max-time 30 "https://pypi.org/pypi/$pkg/json")
  printf '%s' "$j" | jq -e '.info.project_urls // {} | to_entries[] | select(.value | test("github.com/ferinazumaDEV/"))' >/dev/null 2>&1 \
    && ok "pypi $pkg -> github.com/ferinazumaDEV" || bad "pypi $pkg: no project URL to github.com/ferinazumaDEV"
  printf '%s' "$j" | jq -r '.info.summary // ""' | grep -qiE 'any LLM|provider-agnostic|bulletproof' && bad "pypi $pkg: retired promise in summary"
done

[ "$fail" -eq 0 ] && echo "SURFACES OK" || { echo "SURFACES: disagreements found"; exit 1; }
