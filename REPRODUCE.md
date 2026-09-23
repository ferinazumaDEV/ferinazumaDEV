# Check this ecosystem without trusting it

Everything here is self-attested. The packages are signed by the repositories that built them, the
datasets are rebuilt by the repositories that publish them, and the audits are run by the person who
wrote the code. That is a complete chain and a completely endogenous one, and the honest thing to say
about it is that **no outsider has ever verified any of it**.

This page exists to make that cheap to change. Three checks, each self-contained, each run on
2026-09-21 on a clean machine before being written down here. You need `git`, `python3`, `curl` and
(for the first one) the GitHub CLI. Nothing needs an account on anything.

If one of them fails for you, that is worth more to this project than if it passes:
[open an issue](https://github.com/ferinazumaDEV/ferinazumaDEV/issues/new) with what you ran and what
you got. A disagreement between your machine and ours is the only kind of evidence this ecosystem
does not already have.

---

## 1. A published package really was built by the repository that claims it (≈2 min)

Takes the bytes from PyPI — not from us — and walks them back to the repository.

```bash
git clone --depth 1 https://github.com/ferinazumaDEV/ferinazumaDEV
cd ferinazumaDEV
bash scripts/verify-releases.sh
```

It checks, for each of the five packages: the bytes PyPI serves match the digests PyPI declares; those
match the `SHA256SUMS` published on the matching GitHub Release; `gh attestation verify` accepts the
build attestation against the owning repository; and PyPI's Integrity API carries a PEP 740 attestation
naming that repository as publisher. **"Could not check" is a failure, not a pass** — that is
deliberate, and the script was tested against three broken cases before it was trusted.

What a pass means: the artefact you can install was built from that repository, on GitHub, and nobody
swapped it afterwards. What it does not mean: that the code inside is any good.

## 2. The published dataset is exactly what the recipes produce (≈3 min)

The Cookbook publishes measurements. This rebuilds them from the recipes and compares.

```bash
git clone --depth 1 https://github.com/ferinazumaDEV/generative-engine-optimization-cookbook
cd generative-engine-optimization-cookbook
python3 tests/test_instruments.py     # 94 conformance checks on the six instruments
bash dataset/build.sh                 # rebuild every measured value from the recipes
git status --porcelain dataset/       # expected: no output at all
```

The last line is the whole point. Empty output means the numbers in the repository are the numbers the
code produces, with no hand-editing anywhere in between. The conformance corpus in the first command
includes **negative controls**: instruments are fed input they must *reject*, because an instrument
only ever seen accepting is not an instrument.

## 3. The archived copy is the tagged copy (≈2 min)

Each of the three works has a DOI. This checks that the deposit behind the DOI contains what the tag
contains, file by file, rather than checking only that the DOI resolves.

```bash
curl -s https://api.datacite.org/dois/10.5281/zenodo.22299644 | python3 -c \
  'import json,sys; a=json.load(sys.stdin)["data"]["attributes"]; print(a["state"], a["titles"][0]["title"])'
```

For the full content comparison, `notes/herramientas-2026-09-21/verificar-zenodo-vs-tag.py` in the
maintainer's working set does it for all three; it downloads both archives and compares the sha256 of
every file, ignoring container metadata (two zips of identical content differ in timestamps).

**Note, 2026-09-23.** Two things moved since the sentence above was written; nothing above is rewritten.

- `ecosystem-manifest.json` lists a fourth DOI: [notebooklm-kb-system](https://github.com/ferinazumaDEV/notebooklm-kb-system),
  kind `tool` (a DOI-bearing tool with no PyPI package), concept DOI 10.5281/zenodo.22554843, licence AGPL-3.0-or-later
  ([Source: CITATION.cff at v0.1.2](https://raw.githubusercontent.com/ferinazumaDEV/notebooklm-kb-system/v0.1.2/CITATION.cff)).
  The one-line DataCite check above works for it unchanged; on 2026-09-23 it printed `findable notebooklm-kb-system`
  ([Source: DataCite](https://api.datacite.org/dois/10.5281/zenodo.22554843)).
- Since 2026-09-22 the release notes of the handbook, the cookbook and notebooklm-kb-system carry the Software Heritage
  *revision* identifier (`swh:1:rev:`, which is the git commit id) and no directory identifier
  ([Source: handbook v0.1.4 release](https://api.github.com/repos/ferinazumaDEV/generative-engine-optimization-handbook/releases/tags/v0.1.4)).
  The manifest therefore has `swhid_dir: null` for those tags and a new field, `swhid_rev`, read the same way: from
  the release body or left null, never assembled. A null there means "not stated in the release notes", not
  "not archived"; the archive copy is whatever Software Heritage's next visit records.

---

## What is deliberately not here

No check that any of this **works**, in the sense of increasing citation in generative engines. That
study is designed and registered with a DOI, and it has no data. The Cookbook's `PROTOCOL.md` says
what it will measure and what it refuses to claim; `AUTOEVALUACION.md` in the ecosystem snapshot scores
that gap at the bottom of its own rubric. Anyone telling you the question is settled — here or
anywhere else — is ahead of the evidence.

**Pointer, 2026-09-23.** The Cookbook's `PROTOCOL.md` now records, in addenda §13-bis and §13-ter dated 2026-09-21,
that four of the five engines the study registered cannot be observed under the protocol's own conditions and that the
fifth answers the wrong query intermittently and silently — a defect in the registered design, recorded rather than
rewritten ([Source: PROTOCOL.md at v0.1.4](https://github.com/ferinazumaDEV/generative-engine-optimization-cookbook/blob/v0.1.4/PROTOCOL.md)).
The paragraph above stays as written: the study still has no data, and now also a documented reason why.

---

## Runs

One row per check per run, appended; earlier rows are never edited. A check that was not run says so.

| Date | Check | Result |
|---|---|---|
| 2026-09-23 | `scripts/ecosystem-manifest.py --check` (committed file of 2026-09-21) | FAIL, exit 1: handbook and cookbook `latest_tag` v0.1.3 in the manifest, v0.1.4 live; `swhid_dir` null live for both (see note under check 3) |
| 2026-09-23 | `scripts/ecosystem-manifest.py --write` then `--check` | 9 items written; `ok    the manifest matches what is published`, exit 0 |
| 2026-09-23 | check 1, `scripts/verify-releases.sh` | 5 of 5 packages, 25 `ok` lines, 0 `FAIL`, exit 0 |
| 2026-09-23 | `scripts/check-surfaces.sh` | 25 `ok`, 0 `FAIL`, exit 0 |
| 2026-09-23 | check 2, dataset rebuild | not run in this pass |
| 2026-09-23 | check 3, full Zenodo-vs-tag comparison | not run in this pass; only the one-line DataCite state check |
