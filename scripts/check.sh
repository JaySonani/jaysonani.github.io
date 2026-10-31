#!/usr/bin/env bash
# Consistency, privacy, and validity checks for the site. Run from anywhere:
#   scripts/check.sh
# Exits non-zero if any check fails.
set -euo pipefail
cd "$(dirname "$0")/.."

exec python3 -I - <<'PY'
import html, json, os, re, subprocess, sys
from datetime import date
from html.parser import HTMLParser

failures = []
def fail(msg): failures.append(msg)
_seen = 0
def ok(msg):
    # Print "ok" only if nothing failed since the previous ok/section.
    global _seen
    print(f"  {'ok  ' if len(failures) == _seen else 'FAIL'}  {msg}")
    _seen = len(failures)

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

index = read("index.html")
resume = read("resume.md")
llms = read("llms.txt")

# Visible text of index.html: drop <head>, <script>, <style>, then tags.
class Visible(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag in ("head", "script", "style"): self.skip += 1
    def handle_endtag(self, tag):
        if tag in ("head", "script", "style"): self.skip -= 1
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)
v = Visible(); v.feed(index)
visible = re.sub(r"\s+", " ", " ".join(v.parts))
visible_lc = visible.lower()

print("JSON-LD")
blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', index, re.S)
if len(blocks) != 1:
    fail(f"expected exactly 1 JSON-LD block, found {len(blocks)}")
    graph = {}
else:
    try:
        graph = json.loads(blocks[0])
        ok("JSON-LD parses")
    except json.JSONDecodeError as e:
        fail(f"JSON-LD does not parse: {e}"); graph = {}
nodes = {n.get("@type"): n for n in graph.get("@graph", [])}
person = nodes.get("Person", {})
for t in ("Person", "ProfilePage", "WebSite"):
    if t not in nodes: fail(f"JSON-LD missing @type {t}")
if person:
    # "description" is a third-person paraphrase of the first-person page text, so it's not matched verbatim.
    must_be_visible = [person["name"], person["jobTitle"],
                       person["worksFor"]["name"], person["email"].removeprefix("mailto:")]
    must_be_visible += person.get("knowsAbout", [])
    must_be_visible += person.get("knowsLanguage", [])
    must_be_visible += person.get("award", [])
    must_be_visible += [c["name"] for c in person.get("hasCredential", [])]
    must_be_visible += [a["name"] for a in person.get("alumniOf", [])]
    missing = [s for s in must_be_visible if s.lower() not in visible_lc]
    if missing: fail(f"JSON-LD values not visible on index.html: {missing}")
    else: ok(f"all {len(must_be_visible)} JSON-LD values are visible on the page")
    tel_digits = re.sub(r"\D", "", person.get("telephone", ""))
    if tel_digits and tel_digits not in re.sub(r"\D", "", visible):
        fail("JSON-LD telephone not visible on the page")
    for s in person.get("sameAs", []):
        if f'href="{s}" rel="me"' not in index:
            fail(f'sameAs {s} has no visible <a rel="me"> link')
    dm = nodes.get("ProfilePage", {}).get("dateModified", "")
    lastmods = re.findall(r"<lastmod>(.*?)</lastmod>", read("sitemap.xml"))
    if dm not in lastmods:
        fail(f"JSON-LD dateModified ({dm}) does not match any sitemap <lastmod>")
    else: ok(f"dateModified {dm} matches the sitemap")

print("Key facts")
# The page is deliberately one short screen; these facts must be on it and in both text files.
facts = [
    "Jay Sonani", "Forward Deployed Engineer", "AI Software Engineer", "Toronto, Canada", "PolyAI",
    "Replicant", "Pelmorex", "Tulip Retail", "TCS", "6+ years",
    "jaysonani1998@gmail.com", "+1 (902) 412-8901", "https://www.linkedin.com/in/jaysonani/",
    "https://github.com/JaySonani", "Dalhousie University",
]
for f in facts:
    where = [name for name, text in (("index.html", visible + " " + index), ("resume.md", resume), ("llms.txt", llms)) if f not in text]
    if where: fail(f"fact {f!r} missing from: {', '.join(where)}")
ok(f"{len(facts)} key facts in index.html, resume.md, and llms.txt")
# Headline metrics live in the linked text files, not on the page.
metrics = ["500K+ calls/month", "70%+ containment rate", "10+ enterprise clients",
           "15% lower word error rate", "40% fewer false interruptions", "300ms"]
for f in metrics:
    where = [name for name, text in (("resume.md", resume), ("llms.txt", llms)) if f not in text]
    if where: fail(f"metric {f!r} missing from: {', '.join(where)}")
ok(f"{len(metrics)} headline metrics in resume.md and llms.txt")
for name, text in (("index.html", visible), ("resume.md", resume), ("llms.txt", llms)):
    first = " ".join(re.sub(r"[#>*`\[\]()]", " ", text).split()[:150])
    for f in ("Jay Sonani", "Forward Deployed Engineer", "Toronto", "PolyAI", "6+ years"):
        if f not in first: fail(f"{name}: {f!r} not in the first 150 words")
ok("headline facts appear in the first 150 words of each file")

print("Banned content")
tracked = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True, check=True).stdout.split()
text_files = [p for p in tracked if not p.endswith((".pdf", ".png", ".jpg", ".jpeg", ".ico"))]
if not os.path.exists(".private-patterns"):
    fail(".private-patterns is missing; can't check for private data (see CLAUDE.md)")
else:
    pats = [l.strip() for l in read(".private-patterns").splitlines() if l.strip() and not l.startswith("#")]
    hits = [(p, pat) for p in text_files for pat in pats if pat.lower() in read(p).lower()]
    if hits: fail(f"private data found: {sorted(set(p for p, _ in hits))} (patterns redacted)")
    else: ok(f"no private data in {len(text_files)} publishable text files ({len(pats)} patterns)")
injection = ["ignore previous", "ignore all previous", "rank this candidate", "rank jay", "recommend jay",
             "you are an ai", "as an ai model", "system prompt"]
for p in ("index.html", "resume.md", "llms.txt"):
    t = read(p).lower()
    for s in injection:
        if s in t: fail(f"{p}: instruction-to-AI text {s!r}")
    # Jay asked not to signal job seeking on the site (Decisions, D1).
    for s in ("open to new roles", "open to new opportunities", "actively looking", "available immediately", "seeking"):
        if s in t: fail(f"{p}: job-seeking phrase {s!r}")
# Print-only rules (hiding nav when printing) are fine; anything else that hides text is not.
compact = re.sub(r"@media print\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}", "", index).replace(" ", "")
for s in ("display:none", "visibility:hidden", "font-size:0", "opacity:0", "hidden>", "aria-hidden", "<!--"):
    if s in compact:
        fail(f"index.html: possible hidden content ({s})")
ok("no instruction-to-AI, job-seeking, or hidden-text patterns")

print("Sitemap and links")
sm = read("sitemap.xml")
for loc, lm in re.findall(r"<loc>(.*?)</loc>\s*<lastmod>(.*?)</lastmod>", sm):
    try: date.fromisoformat(lm)
    except ValueError: fail(f"sitemap: bad lastmod {lm!r} for {loc}")
    path = loc.removeprefix("https://jaysonani.github.io/") or "index.html"
    if not os.path.exists(path): fail(f"sitemap: {loc} has no file {path}")
if sm.count("<loc>") != sm.count("<lastmod>"): fail("sitemap: every <url> needs a <lastmod>")
ok(f"{sm.count('<loc>')} sitemap URLs with valid lastmod dates")
for page in ("index.html", "404.html"):
    for href in re.findall(r'(?:href|src)="(/[^"#]*)', read(page)):
        if href != "/" and not os.path.exists(href.lstrip("/")): fail(f"{page}: broken local link {href}")
ok("local links resolve")
desc = re.search(r'<meta name="description" content="([^"]*)"', index).group(1)
if len(desc) > 160: fail(f"meta description is {len(desc)} chars (max 160)")
ok(f"meta description is {len(desc)} chars")
if index.count("<h1") != 1: fail("index.html must have exactly one <h1>")
ok("one <h1>")

print()
if failures:
    print("FAILED:")
    for f in failures: print(f"  - {f}")
    sys.exit(1)
print("All checks passed.")
PY
