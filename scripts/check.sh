#!/usr/bin/env bash
# Consistency, privacy, and validity checks for the site. Run from anywhere:
#   scripts/check.sh
# Exits non-zero if any check fails.
set -euo pipefail
cd "$(dirname "$0")/.."

exec python3 -I - <<'PY'
import json, os, re, subprocess, sys
from datetime import date
from html.parser import HTMLParser

SITE = "https://jaysonani.github.io/"
PAGES = ["index.html", "resume/index.html"]  # every indexable HTML page

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

class Visible(HTMLParser):
    """Text a reader sees: drops <head>, <script>, <style>."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip, self.parts = 0, []
    def handle_starttag(self, tag, attrs):
        if tag in ("head", "script", "style"): self.skip += 1
    def handle_endtag(self, tag):
        if tag in ("head", "script", "style"): self.skip -= 1
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)

def visible_text(src):
    v = Visible(); v.feed(src)
    return re.sub(r"\s+", " ", " ".join(v.parts))

html = {p: read(p) for p in PAGES}
visible = {p: visible_text(src) for p, src in html.items()}
resume, llms = read("resume.md"), read("llms.txt")
lastmods = re.findall(r"<lastmod>(.*?)</lastmod>", read("sitemap.xml"))

for page in PAGES:
    src, vis = html[page], visible[page]
    vis_lc = vis.lower()
    print(f"{page}: head and JSON-LD")
    blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', src, re.S)
    graph = {}
    if len(blocks) != 1:
        fail(f"{page}: expected exactly 1 JSON-LD block, found {len(blocks)}")
    else:
        try: graph = json.loads(blocks[0])
        except json.JSONDecodeError as e: fail(f"{page}: JSON-LD does not parse: {e}")
    ok("JSON-LD parses")
    nodes = {n.get("@type"): n for n in graph.get("@graph", [])}
    person = nodes.get("Person", {})
    if not person: fail(f"{page}: JSON-LD has no Person")
    if person.get("@id") != SITE + "#person": fail(f"{page}: Person @id must be {SITE}#person")
    # "description" is a third-person paraphrase of the first-person page text, so it's not matched verbatim.
    must = [person.get("name", ""), person.get("jobTitle", ""), person.get("worksFor", {}).get("name", ""),
            person.get("email", "").removeprefix("mailto:")]
    must += person.get("knowsAbout", []) + person.get("knowsLanguage", []) + person.get("award", [])
    must += [c["name"] for c in person.get("hasCredential", [])]
    must += [a["name"] for a in person.get("alumniOf", [])]
    missing = [s for s in must if s.lower() not in vis_lc]
    if missing: fail(f"{page}: JSON-LD values not visible on the page: {missing}")
    ok(f"all {len(must)} JSON-LD values are visible on the page")
    tel = re.sub(r"\D", "", person.get("telephone", ""))
    if tel and tel not in re.sub(r"\D", "", vis): fail(f"{page}: JSON-LD telephone not visible")
    for s in person.get("sameAs", []):
        if f'href="{s}" rel="me"' not in src: fail(f'{page}: sameAs {s} has no visible <a rel="me"> link')
    page_node = nodes.get("ProfilePage") or nodes.get("WebPage") or {}
    if page_node.get("dateModified") not in lastmods:
        fail(f"{page}: dateModified {page_node.get('dateModified')!r} matches no sitemap <lastmod>")
    ok("telephone, rel=me links, and dateModified")
    canon = re.search(r'<link rel="canonical" href="([^"]+)"', src)
    want = SITE + page.removesuffix("index.html")
    if not canon or canon.group(1) != want: fail(f"{page}: canonical should be {want}")
    if want not in read("sitemap.xml"): fail(f"{page}: {want} missing from sitemap.xml")
    desc = re.search(r'<meta name="description" content="([^"]*)"', src)
    if not desc or len(desc.group(1)) > 160: fail(f"{page}: meta description missing or over 160 chars")
    title = re.search(r"<title>(.*?)</title>", src).group(1)
    if "Jay Sonani" not in title: fail(f"{page}: <title> must contain the name")
    if src.count("<h1") != 1: fail(f"{page}: must have exactly one <h1>")
    for tag in ('og:title', 'og:description', 'og:url', 'og:image'):
        if f'property="{tag}"' not in src: fail(f"{page}: missing {tag}")
    ok(f"canonical, sitemap entry, title, description ({len(desc.group(1)) if desc else 0} chars), one <h1>, Open Graph")

print("Key facts")
# Facts every page and both text files must state.
facts = ["Jay Sonani", "Forward Deployed Engineer", "AI Software Engineer", "Toronto, Canada", "PolyAI",
         "Replicant", "Pelmorex", "Tulip Retail", "TCS", "6+ years", "jaysonani1998@gmail.com",
         "+1 (902) 412-8901", "https://www.linkedin.com/in/jaysonani/", "https://github.com/JaySonani"]
texts = {p: visible[p] + " " + html[p] for p in PAGES} | {"resume.md": resume, "llms.txt": llms}
for f in facts:
    where = [n for n, t in texts.items() if f not in t]
    if where: fail(f"fact {f!r} missing from: {', '.join(where)}")
ok(f"{len(facts)} key facts in {', '.join(texts)}")
# The home page says "Dal" (Jay's choice); the full name stays everywhere else.
for n, t in texts.items():
    if n != "index.html" and "Dalhousie University" not in t: fail(f"'Dalhousie University' missing from {n}")
if ">Dal</a>" not in html["index.html"]: fail("index.html: expected the 'Dal' link")
ok("school named in full on resume page and text files, 'Dal' on home")
# Headline metrics: the home page is one short screen, so they live in the resume page and text files.
metrics = ["500K+ calls/month", "70%+ containment rate", "10+ enterprise clients",
           "15% lower word error rate", "40% fewer false interruptions", "300ms"]
for f in metrics:
    where = [n for n, t in (("resume/index.html", visible["resume/index.html"]), ("resume.md", resume), ("llms.txt", llms)) if f not in t]
    if where: fail(f"metric {f!r} missing from: {', '.join(where)}")
ok(f"{len(metrics)} headline metrics in resume/index.html, resume.md, and llms.txt")
for name, text in [(p, visible[p]) for p in PAGES] + [("resume.md", resume), ("llms.txt", llms)]:
    first = " ".join(re.sub(r"[#>*`\[\]()]", " ", text).split()[:150])
    for f in ("Jay Sonani", "Forward Deployed Engineer", "Toronto", "PolyAI", "6+ years"):
        if f not in first: fail(f"{name}: {f!r} not in the first 150 words")
ok("headline facts appear in the first 150 words of each file")

print("Banned content")
tracked = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True, check=True).stdout.split()
text_files = [p for p in tracked if not p.endswith((".pdf", ".png", ".jpg", ".jpeg", ".ico"))]
if not os.path.exists(".private-patterns"):
    fail(".private-patterns is missing; can't check for private data")
else:
    pats = [l.strip() for l in read(".private-patterns").splitlines() if l.strip() and not l.startswith("#")]
    hits = [(p, pat) for p in text_files for pat in pats if pat.lower() in read(p).lower()]
    if hits: fail(f"private data found: {sorted(set(p for p, _ in hits))} (patterns redacted)")
    ok(f"no private data in {len(text_files)} publishable text files ({len(pats)} patterns)")
injection = ["ignore previous", "ignore all previous", "rank this candidate", "rank jay", "recommend jay",
             "you are an ai", "as an ai model", "system prompt"]
for p in PAGES + ["resume.md", "llms.txt"]:
    t = read(p).lower()
    for s in injection:
        if s in t: fail(f"{p}: instruction-to-AI text {s!r}")
    # Jay asked not to signal job seeking on the site (Decisions, D1).
    for s in ("open to new roles", "open to new opportunities", "actively looking", "available immediately", "seeking"):
        if s in t: fail(f"{p}: job-seeking phrase {s!r}")
for p in PAGES:
    compact = html[p].replace(" ", "")
    for s in ("display:none", "visibility:hidden", "font-size:0", "opacity:0", "hidden>", "aria-hidden", "<!--"):
        if s in compact: fail(f"{p}: possible hidden content ({s})")
ok("no instruction-to-AI, job-seeking, or hidden-text patterns")

print("Sitemap and links")
sm = read("sitemap.xml")
for loc, lm in re.findall(r"<loc>(.*?)</loc>\s*<lastmod>(.*?)</lastmod>", sm):
    try: date.fromisoformat(lm)
    except ValueError: fail(f"sitemap: bad lastmod {lm!r} for {loc}")
    path = loc.removeprefix(SITE) or "index.html"
    if path.endswith("/"): path += "index.html"
    if not os.path.exists(path): fail(f"sitemap: {loc} has no file {path}")
if sm.count("<loc>") != sm.count("<lastmod>"): fail("sitemap: every <url> needs a <lastmod>")
ok(f"{sm.count('<loc>')} sitemap URLs with valid lastmod dates and existing files")
for page in PAGES + ["404.html"]:
    for href in re.findall(r'(?:href|src)="(/[^"#]*)', read(page)):
        if href != "/" and not os.path.exists(href.lstrip("/")): fail(f"{page}: broken local link {href}")
for url in re.findall(r"\((https://jaysonani\.github\.io/[^)]*)\)", llms):
    path = url.removeprefix(SITE) or "index.html"
    if path.endswith("/"): path += "index.html"
    if not os.path.exists(path): fail(f"llms.txt: {url} has no file")
ok("local links in pages and llms.txt resolve")
key_files = [f for f in os.listdir(".") if re.fullmatch(r"[0-9a-f]{32}\.txt", f)]
for f in key_files:
    if read(f).strip() != f.removesuffix(".txt"): fail(f"IndexNow key file {f} content doesn't match its name")
ok(f"{len(key_files)} IndexNow key file(s) valid")

print()
if failures:
    print("FAILED:")
    for f in failures: print(f"  - {f}")
    sys.exit(1)
print("All checks passed.")
PY
