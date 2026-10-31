"""Render resume.md into resume/index.html.

Run after editing resume.md:  python3 scripts/make-resume-html.py
The output is a plain static file that gets committed; the site itself has no build step.
Update DATE (and the sitemap lastmod dates) when the content changes, then run scripts/check.sh.
"""
import html, json, os, re, sys

repo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
md = open(f"{repo}/resume.md", encoding="utf-8").read()
E = html.escape
SITE = "https://jaysonani.github.io/"
DATE = "2026-10-31"
MONTHS = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}

def sections(text):
    out, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"^## (.+)$", line)
        if m:
            cur = m.group(1); out[cur] = []
        elif cur:
            out[cur].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}

S = sections(md)
URL = re.compile(r"(https?://[^\s)]+)")

def linkify(text):
    return URL.sub(lambda m: f'<a href="{E(m.group(1))}">{E(m.group(1))}</a>', E(text))

def bullets(block):
    return [l[2:].strip() for l in block.splitlines() if l.startswith("- ")]

def ym(s):  # "Oct 2025" -> "2025-10"
    mon, yr = s.split()
    return f"{yr}-{MONTHS[mon]:02d}"

def timeify(dates):  # "Oct 2025 – Present"
    parts = [p.strip() for p in dates.split("–")]
    if len(parts) == 2 and re.fullmatch(r"[A-Z][a-z]{2}", parts[0]):  # "Sep – Dec 2022" style
        parts[0] = f"{parts[0]} {parts[1].split()[-1]}"
    out = []
    for p in parts:
        out.append(p if p == "Present" else f'<time datetime="{ym(p)}">{E(p)}</time>')
    return " – ".join(out)

# Experience
jobs_html = []
for block in re.split(r"^### ", S["Experience"], flags=re.M)[1:]:
    head, _, rest = block.partition("\n")
    m = re.match(r"(.+?), (.+) \(([^()]+?–[^()]+?)\) · (.+)$", head.strip())
    title, org, dates, loc = m.groups()
    items = "\n".join(f"      <li>{E(b)}</li>" for b in bullets(rest))
    jobs_html.append(f"""  <article>
    <h3>{E(title)}, {E(org)}</h3>
    <p class="meta">{timeify(dates)} · {E(loc)}</p>
    <ul>
{items}
    </ul>
  </article>""")

def simple_list(name, fn=linkify):
    return "\n".join(f"    <li>{fn(b)}</li>" for b in bullets(S[name]))

def skills_list():
    rows = []
    for b in bullets(S["Skills"]):
        k, _, v = b.partition(": ")
        rows.append(f"    <li><strong>{E(k)}:</strong> {E(v)}</li>")
    return "\n".join(rows)

def projects_list():
    rows = []
    for b in bullets(S["Projects"]):
        m = re.match(r"(.+?) \((\w{3} \d{4})\): (.+?) (https://\S+)$", b)
        name, d, desc, url = m.groups()
        rows.append(f'    <li><a href="{E(url)}">{E(name)}</a> (<time datetime="{ym(d)}">{E(d)}</time>): {E(desc)}</li>')
    return "\n".join(rows)

def certs_list():
    rows = []
    for b in bullets(S["Certifications"]):
        m = re.match(r"(.+?), ([^,]+?) \((.+?)\)(?:: (https://\S+))?$", b)
        if not m:  # "Applied Data Science I: ..., with honors, WorldQuant University (Jun 2021)"
            rows.append(f"    <li>{E(b)}</li>"); continue
        name, issuer, when, url = m.groups()
        label = f'<a href="{E(url)}">{E(name)}</a>' if url else E(name)
        rows.append(f"    <li>{label}, {E(issuer)} ({E(when)})</li>")
    return "\n".join(rows)

summary = S["Summary"]
skills_flat = []
for b in bullets(S["Skills"]):
    for item in b.partition(": ")[2].split(", "):
        skills_flat.append(item.strip())

# Credentials for JSON-LD (only what's visible on this page)
creds = [
    ("NVIDIA-Certified Associate: Generative AI LLMs", "certification", "NVIDIA", "2025-03", "2027-03", "https://credential.nvidia.com/346c4d82-30a9-4ee1-a24e-c96c78ee842a"),
    ("Generative AI Fundamentals", "certification", "Databricks", "2025-01", "2027-01", "https://credentials.databricks.com/46f694fa-ee6f-404a-85fb-4f6fa73ed99a"),
    ("Claude Code in Action", "certificate", "Anthropic", "2025-07", None, "https://github.com/JaySonani/Certifications/blob/master/Claude%20Code%20in%20Action.pdf"),
    ("Introduction to Model Context Protocol", "certificate", "Anthropic", "2025-07", None, "https://github.com/JaySonani/Certifications/blob/master/Intro%20to%20Model%20Context%20Protocol.pdf"),
    ("Introduction to Agent Skills", "certificate", "Anthropic", "2025-07", None, "https://github.com/JaySonani/Certifications/blob/master/Introduction%20to%20Agent%20Skills.pdf"),
    ("Applied Data Science I: Scientific Computing & Python", "certificate", "WorldQuant University", "2021-06", None, None),
    ("Google Cloud Platform Fundamentals: Core Infrastructure", "certificate", "Google", "2020-11", None, None),
    ("Master of Applied Computer Science (M.A.C.S.)", "degree", "Dalhousie University", "2022-12", None, None),
    ("Bachelor of Engineering (B.E.), Computer Engineering", "degree", "Gujarat Technological University", "2020-08", None, None),
]
def cred(c):
    name, cat, org, made, exp, url = c
    d = {"@type": "EducationalOccupationalCredential", "name": name, "credentialCategory": cat,
         "recognizedBy": {"@type": "CollegeOrUniversity" if cat == "degree" else "Organization", "name": org},
         "dateCreated": made}
    if exp: d["expires"] = exp
    if url: d["url"] = url
    return d

DAL = {"@type": "CollegeOrUniversity", "name": "Dalhousie University",
       "sameAs": ["https://www.dal.ca/", "https://en.wikipedia.org/wiki/Dalhousie_University", "https://www.wikidata.org/wiki/Q579321"]}
ld = {
    "@context": "https://schema.org",
    "@graph": [
        {"@type": "WebPage", "@id": SITE + "resume/#webpage", "url": SITE + "resume/",
         "name": "Jay Sonani · Resume", "inLanguage": "en-CA", "dateModified": DATE,
         "isPartOf": {"@id": SITE + "#website"}, "about": {"@id": SITE + "#person"},
         "mainEntity": {"@id": SITE + "#person"}, "breadcrumb": {"@id": SITE + "resume/#breadcrumb"}},
        {"@type": "BreadcrumbList", "@id": SITE + "resume/#breadcrumb", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Jay Sonani", "item": SITE},
            {"@type": "ListItem", "position": 2, "name": "Resume", "item": SITE + "resume/"}]},
        {"@type": "Person", "@id": SITE + "#person", "name": "Jay Sonani", "url": SITE,
         "jobTitle": "Forward Deployed Engineer",
         "email": "mailto:jaysonani1998@gmail.com", "telephone": "+1-902-412-8901",
         "worksFor": {"@type": "Organization", "name": "PolyAI", "url": "https://poly.ai/", "sameAs": "https://www.linkedin.com/company/polyai/"},
         "address": {"@type": "PostalAddress", "addressLocality": "Toronto", "addressRegion": "ON", "addressCountry": "CA"},
         "alumniOf": [DAL, {"@type": "CollegeOrUniversity", "name": "Gujarat Technological University"}],
         "knowsAbout": skills_flat,
         "knowsLanguage": [l.strip() for l in S["Languages"].split(",")],
         "hasCredential": [cred(c) for c in creds],
         "award": bullets(S["Awards"]),
         "sameAs": ["https://www.linkedin.com/in/jaysonani/", "https://github.com/JaySonani"]},
    ],
}

desc = "Resume of Jay Sonani, Forward Deployed Engineer at PolyAI, Toronto: LLM voice AI agents, 500K+ calls/month, 10+ enterprise clients, 6+ years."
assert len(E(desc)) <= 160, len(E(desc))
langs = E(S["Languages"])

page = f"""<!DOCTYPE html>
<html lang="en-CA">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jay Sonani · Resume · Forward Deployed Engineer · Toronto</title>
<meta name="description" content="{E(desc)}">
<meta name="author" content="Jay Sonani">
<link rel="canonical" href="{SITE}resume/">
<meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large">
<link rel="alternate" type="text/markdown" href="/resume.md" title="Resume (Markdown)">
<link rel="alternate" type="text/plain" href="/llms.txt" title="LLM-readable summary">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<meta name="theme-color" content="#ffffff">
<meta name="color-scheme" content="light">
<meta property="og:type" content="profile">
<meta property="og:locale" content="en_CA">
<meta property="og:site_name" content="Jay Sonani">
<meta property="og:title" content="Jay Sonani · Resume · Forward Deployed Engineer">
<meta property="og:description" content="{E(desc)}">
<meta property="og:url" content="{SITE}resume/">
<meta property="og:image" content="{SITE}assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Jay Sonani · Forward Deployed Engineer · AI Engineer · Toronto, Canada">
<meta property="profile:first_name" content="Jay">
<meta property="profile:last_name" content="Sonani">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Jay Sonani · Resume · Forward Deployed Engineer">
<meta name="twitter:description" content="{E(desc)}">
<meta name="twitter:image" content="{SITE}assets/og-image.png">
<script type="application/ld+json">
{json.dumps(ld, indent=2, ensure_ascii=False)}
</script>
<style>
body{{margin:0;background:#fff;color:#000;font:14px/1.6 Consolas,"SF Mono",Menlo,Monaco,"Liberation Mono","Courier New",monospace}}
main{{max-width:84ch;padding:3.5rem 4.5vw}}
h1{{font-size:1.15em;margin:0 0 .3rem}}
h2{{font-size:1em;margin:2rem 0 .6rem}}
h3{{font-size:1em;margin:0}}
p,ul{{margin:0 0 1rem}}
ul{{padding-left:2.2em}}
li{{margin:.15rem 0}}
article{{margin-bottom:1.2rem}}
.meta{{margin:0 0 .3rem;color:#333}}
a,a:visited{{color:#0000ee}}
@media (max-width:600px){{body{{font-size:13px;line-height:1.5}}main{{padding:1.25rem 1.1rem}}ul{{padding-left:1.4em}}}}
</style>
</head>
<body>
<main>
<p><a href="/">← home</a></p>
<h1>Jay Sonani</h1>
<p>Forward Deployed Engineer · AI Engineer (LLM agents, voice AI) · Toronto, Canada</p>
<p><a href="mailto:jaysonani1998@gmail.com">jaysonani1998@gmail.com</a> · <a href="tel:+19024128901">+1 (902) 412-8901</a> · <a href="https://www.linkedin.com/in/jaysonani/" rel="me">linkedin</a> · <a href="https://github.com/JaySonani" rel="me">github</a> · <a href="/assets/Jay-Sonani-Resume.pdf">pdf</a> · <a href="/resume.md">markdown</a></p>

<section id="summary">
  <h2>summary</h2>
  <p>{E(summary)}</p>
</section>

<section id="highlights">
  <h2>highlights</h2>
  <ul>
{simple_list("Highlights")}
  </ul>
</section>

<section id="experience">
  <h2>experience</h2>
{chr(10).join(jobs_html)}
</section>

<section id="skills">
  <h2>skills</h2>
  <ul>
{skills_list()}
  </ul>
</section>

<section id="projects">
  <h2>projects</h2>
  <ul>
{projects_list()}
  </ul>
</section>

<section id="certifications">
  <h2>certifications</h2>
  <ul>
{certs_list()}
  </ul>
</section>

<section id="education">
  <h2>education</h2>
  <ul>
{simple_list("Education", E)}
  </ul>
</section>

<section id="awards">
  <h2>awards</h2>
  <ul>
{simple_list("Awards", E)}
  </ul>
</section>

<section id="languages">
  <h2>languages</h2>
  <p>{langs}</p>
</section>
</main>
</body>
</html>
"""
os.makedirs(f"{repo}/resume", exist_ok=True)
open(f"{repo}/resume/index.html", "w", encoding="utf-8").write(page)
print("wrote resume/index.html", len(page), "bytes;", len(jobs_html), "jobs;", len(skills_flat), "skills")
