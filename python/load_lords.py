"""
House of Lords  -  load Lords Hansard and the people behind it into HANSARD.

Odell's "Hansard Speeches 1979-2021" is Commons only, so the Lords come from
the same place Odell's data came from: the TheyWorkForYou / ParlParse daily
XML (one file per sitting day, 1999 on). The ids, person ids and layout match
what the Commons work already uses, so an MP who became a peer has the same
person_id in both Houses and "MPs who became peers" is a plain join.

What it loads:
    hl.SourceSpeech   every speech and procedural line, in sitting order
    hl.Division       every division in the XML, with the counts
    hl.Vote           every peer's vote in them
    hl.Person         everyone in people.json who sat in either House
    hl.Membership     their seats: House, party, peerage type, start/end

    pip install pyodbc requests
    python load_lords.py --sql "Driver={ODBC Driver 18 for SQL Server};Server=.;Database=HANSARD;Trusted_Connection=yes;TrustServerCertificate=yes"

Run sql/00_lords_schema.sql first. The XML is downloaded once into
./_no_upload/lords_xml (about 4-5k files, a few GB). --from / --to limit the years.
If you already have the files (e.g. from
  rsync -az data.theyworkforyou.com::parldata/scrapedxml/lordspages/ _no_upload/lords_xml/
) point --folder at them and add --no-download.

    python load_lords.py --selftest     parses a built-in sample, no server
    python load_lords.py --parse-only   parses the folder and prints counts, no server
"""
from __future__ import annotations

import argparse
import html.entities
import json
import os
import re
import sys
import time
import unicodedata
import xml.etree.ElementTree as ET

INDEX = "https://www.theyworkforyou.com/pwdata/scrapedxml/lordspages/"
PEOPLE = "https://raw.githubusercontent.com/mysociety/parlparse/master/members/people.json"
FILE = re.compile(r"daylord(\d{4}-\d{2}-\d{2})([a-z]+)\.xml")
COL = re.compile(r"/lords/\d{4}-\d{2}-\d{2}[a-z]*\.([A-Z]*)(\d+)\.(\d+)")
ENTITY = re.compile(r"&([A-Za-z][A-Za-z0-9]*);")
XML_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}


# ---------------------------------------------------------------- download

def get(url: str, path: str, min_size: int = 1):
    import requests
    if os.path.exists(path) and os.path.getsize(path) >= min_size:
        return path
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        tmp = path + ".part"
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
        os.replace(tmp, path)
    return path


def latest_files(names, yr_from: int, yr_to: int) -> list[str]:
    """One file per sitting day: the highest version letter wins (a, b, ... z, aa)."""
    best = {}
    for n in names:
        m = FILE.fullmatch(n)
        if not m or not (yr_from <= int(m.group(1)[:4]) <= yr_to):
            continue
        d, v = m.groups()
        if d not in best or (len(v), v) > (len(best[d][0]), best[d][0]):
            best[d] = (v, n)
    return [best[d][1] for d in sorted(best)]


def fetch_xml(folder: str, yr_from: int, yr_to: int, download: bool) -> list[str]:
    os.makedirs(folder, exist_ok=True)
    if download:
        import requests
        page = requests.get(INDEX, timeout=60).text
        names = set(re.findall(r'href="(daylord[^"]+\.xml)"', page))
    else:
        names = set(os.listdir(folder))
    files = latest_files(names, yr_from, yr_to)
    if download:
        for i, n in enumerate(files, 1):
            get(INDEX + n, os.path.join(folder, n))
            print(f"\rdownloaded {i:,}/{len(files):,}  {n}", end="", flush=True)
        print()
    return [os.path.join(folder, n) for n in files]


# ---------------------------------------------------------------- people.json

def lords_name(n: dict) -> str | None:
    pre, lord, of = n.get("honorific_prefix"), n.get("lordname"), n.get("lordofname")
    if not pre or not (lord or of):
        return None
    s = f"{pre} {lord}" if lord else pre
    return f"{s} of {of}" if of else s


def load_people(path: str):
    """Returns (persons, memberships, lord id -> person id)."""
    d = json.load(open(path, encoding="utf-8"))
    posts = {p["id"]: p for p in d["posts"]}
    lord_to_person, redirects = {}, {}
    members = []
    for m in d["memberships"]:
        if "redirect" in m:
            redirects[m["id"]] = m["redirect"]
            continue
        post = posts.get(m.get("post_id"))
        if m.get("organization_id") == "house-of-lords":
            house = "Lords"
            lord_to_person[m["id"]] = m["person_id"]
        elif post and post.get("organization_id") == "house-of-commons":
            house = "Commons"
        else:
            continue                                   # devolved bodies, the Crown
        peerage = next((i["identifier"] for i in m.get("identifiers", []) if i["scheme"] == "peeragetype"), None)
        members.append((m["id"][:100], m["person_id"][:100], house, peerage, (m.get("on_behalf_of_id") or None),
                        (post or {}).get("area", {}).get("name") if house == "Commons" else None,
                        date_or_none(m.get("start_date")), date_or_none(m.get("end_date")),
                        m.get("start_reason"), m.get("end_reason")))
    for old, new in redirects.items():
        if new in lord_to_person:
            lord_to_person[old] = lord_to_person[new]
    in_house = {m[1] for m in members}
    persons = []
    for p in d["persons"]:
        if p["id"] not in in_house:
            continue
        ids = {i["scheme"]: i["identifier"] for i in p.get("identifiers", [])}
        names = p.get("other_names", [])
        lord = next((s for s in map(lords_name, names) if s), None)
        main = next((n for n in names if n.get("note") == "Main" and n.get("family_name")), names[0] if names else {})
        given, surname = main.get("given_name"), main.get("family_name") or main.get("surname")
        plain = " ".join(x for x in (given, surname) if x) or None
        persons.append((p["id"][:100], int(ids["datadotparl_id"]) if ids.get("datadotparl_id", "").isdigit() else None,
                        lord or plain, given, surname))
    return persons, members, lord_to_person


NICK_PAIRS = [("Tim", "Timothy"), ("Tom", "Thomas"), ("Tony", "Antony"), ("Tony", "Anthony"), ("Jeff", "Jeffrey"),
              ("Bob", "Robert"), ("Bill", "William"), ("Jim", "James"), ("Dick", "Richard"), ("Ted", "Edward"),
              ("Ed", "Edward"), ("Chris", "Christopher"), ("Mike", "Michael"), ("Andy", "Andrew"), ("Nick", "Nicholas"),
              ("Pat", "Patrick"), ("Ron", "Ronald"), ("Archy", "Archibald"), ("Archie", "Archibald"), ("Ken", "Kenneth"),
              ("Dave", "David"), ("Steve", "Stephen"), ("Alex", "Alexander"), ("Sam", "Samuel"), ("Ben", "Benjamin"),
              ("Dan", "Daniel"), ("Matt", "Matthew"), ("Pete", "Peter"), ("Joe", "Joseph"), ("Fred", "Frederick"),
              ("Geoff", "Geoffrey"), ("Gerry", "Gerald"), ("Harry", "Henry"), ("Liz", "Elizabeth"), ("Sue", "Susan"),
              ("Jo", "Joanna"), ("Win", "Winifred"), ("Bernie", "Bernard"), ("Des", "Desmond"), ("Don", "Donald"),
              ("Phil", "Philip"), ("Rob", "Robert"), ("Greg", "Gregory"), ("Doug", "Douglas"), ("Ray", "Raymond"),
              ("Les", "Leslie"), ("Len", "Leonard"), ("Stan", "Stanley"), ("Wal", "Walter"), ("Ian", "Iain")]
NICKNAMES: dict[str, set[str]] = {}
for _a, _b in NICK_PAIRS:
    NICKNAMES.setdefault(_a, set()).add(_b)
    NICKNAMES.setdefault(_b, set()).add(_a)

PREFIXES = re.compile(r"^(the reverend|the rev|rev|sir|dr|mr|mrs|ms|miss|dame|lady)\.?\s+", re.I)


def person_names(path: str, keep: set[str]) -> list[tuple[str, str]]:
    """Every way a person might be written in the Commons: given + family, the first
    of their formal names + family ('Antony Newton', 'Jeremy Ashdown'), each family
    name they've had ('Margaret Jackson', 'Margaret Beckett') and ParlParse's
    alternates. Odell's DisplayAs is matched against these."""
    d = json.load(open(path, encoding="utf-8"))
    out = set()
    for p in d["persons"]:
        if p["id"] not in keep:
            continue
        names, firsts, families = set(), set(), set()
        for n in p.get("other_names", []):
            if n.get("name"):
                names.add(n["name"])
            fam = n.get("family_name") or n.get("surname")
            if fam:
                families.add(fam)
                if n.get("given_name"):
                    names.add(f"{n['given_name']} {fam}")
            for g, every in ((n.get("given_name"), False), (n.get("additional_name"), True)):
                g = PREFIXES.sub("", g or "").split()
                firsts.update(g if every else g[:1])
        if not families:                                # peers with only a title: use the title name
            families = {n["lordname"] for n in p.get("other_names", []) if n.get("lordname")}
        for f in list(firsts):
            firsts.update(NICKNAMES.get(f, ()))
        names.update(f"{f} {fam}" for f in firsts for fam in families)
        initials = {w[0] for n in p.get("other_names", []) for w in (n.get("additional_name") or "").split()[1:]}
        names.update(f"{f} {i}. {fam}" for f in firsts for i in initials for fam in families)   # 'John M. Taylor'
        names.update(re.sub(r"\b([A-Z])\b(?!\.)", r"\1.", x) for x in list(names))            # 'Brian H' -> 'Brian H.'
        seen = set()                                    # SQL Server's key ignores case: 'McAvoy' = 'Mcavoy'
        for name in sorted(names):
            clean = " ".join(PREFIXES.sub("", unicodedata.normalize("NFC", html.unescape(name))).split())[:400]   # people.json has some &ouml;
            if clean and clean.casefold() not in seen:
                seen.add(clean.casefold())
                out.add((p["id"][:100], clean))
    return sorted(out)


def date_or_none(s):
    """people.json dates can be '1918' or '1997-05-01'; keep only full dates."""
    return s if s and len(s) == 10 else None


# ---------------------------------------------------------------- the XML

XML_DECL = re.compile(r"^\s*<\?xml[^>]*\?>")


def read_xml(path: str) -> str:
    """The daily files declare their own encoding (ISO-8859-1 for most years), so honour it."""
    data = open(path, "rb").read()
    m = re.match(rb'\s*<\?xml[^>]*encoding="([^"]+)"', data)
    return data.decode(m.group(1).decode("ascii") if m else "utf-8", errors="replace")


def unentity(raw: str) -> str:
    """ParlParse text can carry HTML named entities (&nbsp;, &mdash;) that XML doesn't define."""
    def sub(m):
        name = m.group(1)
        if name in XML_ENTITIES:
            return m.group(0)
        ch = html.entities.html5.get(name + ";")
        return ch if ch else m.group(0)
    return ENTITY.sub(sub, raw)


def body_of(el) -> str | None:
    paras = [" ".join("".join(p.itertext()).split()) for p in el.iter() if p.tag in ("p", "table")]
    paras = [p for p in paras if p]
    if not paras:
        s = " ".join("".join(el.itertext()).split())
        return s or None
    return "\n".join(paras)


def location_and_col(gid: str, colnum: str | None):
    m = COL.search(gid or "")
    prefix = m.group(1) if m else ""
    return ("Chamber" if not prefix else prefix)[:10], (colnum or (m and f"{prefix}{m.group(2)}") or None)


def parse_day(path_or_text: str, from_text: bool = False):
    """Yields ('speech', row) / ('division', row) / ('vote', row) for one sitting day."""
    raw = path_or_text if from_text else read_xml(path_or_text)
    root = ET.fromstring(unentity(XML_DECL.sub("", raw, count=1)))
    m = FILE.search(os.path.basename(path_or_text)) if not from_text else None
    major = minor = None
    seq = 0
    for el in root:
        tag = el.tag
        if tag == "major-heading":
            major, minor = " ".join("".join(el.itertext()).split())[:400] or None, None
            continue
        if tag == "minor-heading":
            minor = " ".join("".join(el.itertext()).split())[:400] or None
            continue
        if tag not in ("speech", "division"):
            continue                                    # gidredirect, oral-heading etc.
        gid = el.get("id") or ""
        date = el.get("divdate") or (re.search(r"(\d{4}-\d{2}-\d{2})", gid) or m).group(1)
        seq += 1
        if tag == "speech":
            loc, col = location_and_col(gid, el.get("colnum"))
            yield "speech", (gid[:100], date, seq, loc, (col or "")[:20] or None, (el.get("time") or "")[:10] or None,
                             "Procedural" if el.get("nospeaker") == "true" else "Speech",
                             (el.get("speakername") or "")[:400] or None, (el.get("person_id") or "")[:100] or None,
                             (el.get("speakerid") or "")[:100] or None, major, minor, body_of(el))
        else:
            cnt = el.find("divisioncount")
            num = lambda k: int(cnt.get(k)) if cnt is not None and (cnt.get(k) or "").isdigit() else None
            dn = el.get("divnumber")
            yield "division", (gid[:100], date, int(dn) if dn and dn.isdigit() else None, seq, major, minor,
                               num("content"), num("not-content"))
            for lst in el.iter("lordlist"):
                for lord in lst.iter("lord"):
                    yield "vote", (gid[:100], (lord.get("person_id") or "")[:100] or None,
                                   (lord.get("id") or "")[:100] or None,
                                   " ".join("".join(lord.itertext()).split())[:400] or None,
                                   (lord.get("vote") or lst.get("vote") or "")[:20],
                                   1 if lord.get("teller") == "yes" else 0)


# ---------------------------------------------------------------- SQL

def insert(cur, cn, sql, rows, sizes=None, batch=5000):
    if not rows:
        return 0
    if sizes:
        cur.setinputsizes(sizes)
    for i in range(0, len(rows), batch):
        cur.executemany(sql, rows[i:i + batch])
    cn.commit()
    return len(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sql", help="ODBC connection string to HANSARD")
    ap.add_argument("--folder", default="_no_upload/lords_xml")
    ap.add_argument("--from", dest="yr_from", type=int, default=1999)
    ap.add_argument("--to", dest="yr_to", type=int, default=2100)
    ap.add_argument("--no-download", action="store_true", help="use only the files already in --folder")
    ap.add_argument("--parse-only", action="store_true", help="parse and count, no server")
    ap.add_argument("--people-only", action="store_true", help="reload only hl.Person, hl.Membership and hl.PersonName")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        return selftest()

    files = [] if a.people_only else fetch_xml(a.folder, a.yr_from, a.yr_to, not a.no_download)
    if not files and not a.people_only:
        sys.exit(f"no daylord*.xml files for {a.yr_from}-{a.yr_to} in {a.folder}")
    people_path = get(PEOPLE, os.path.join(a.folder, "people.json"), 1_000_000)
    persons, members, lord_to_person = load_people(people_path)
    names = person_names(people_path, {p[0] for p in persons})
    print(f"{len(persons):,} people, {len(members):,} seats, {len(files):,} sitting days")

    if a.parse_only:
        n = {"speech": 0, "division": 0, "vote": 0}
        for i, f in enumerate(files, 1):
            for kind, _ in parse_day(f):
                n[kind] += 1
            print(f"\r{i:,}/{len(files):,}  {n}", end="", flush=True)
        print()
        return
    if not a.sql:
        sys.exit("--sql is required unless --parse-only or --selftest")

    import pyodbc
    cn = pyodbc.connect(a.sql, autocommit=False)
    cur = cn.cursor()
    if cur.execute("SELECT OBJECT_ID('hl.SourceSpeech')").fetchone()[0] is None:
        sys.exit("hl.SourceSpeech doesn't exist - run sql/00_lords_schema.sql first")
    if cur.execute("SELECT OBJECT_ID('hl.PersonName')").fetchone()[0] is None:
        sys.exit("hl.PersonName doesn't exist - rerun sql/00_lords_schema.sql (it only adds what's missing)")
    tables = ["hl.Person", "hl.Membership", "hl.PersonName"]
    if not a.people_only:
        tables += ["hl.SourceSpeech", "hl.Division", "hl.Vote"]
    for t in tables:
        cur.execute(f"TRUNCATE TABLE {t}")
    cn.commit()
    cur.fast_executemany = True

    W, V, B = pyodbc.SQL_WVARCHAR, pyodbc.SQL_VARCHAR, pyodbc.SQL_BIGINT
    insert(cur, cn, "INSERT hl.Person (PersonId, DataParlId, DisplayName, GivenName, Surname) VALUES (?,?,?,?,?)",
           persons, [(W, 100, 0), (pyodbc.SQL_INTEGER, 10, 0), (W, 400, 0), (W, 200, 0), (W, 200, 0)])
    insert(cur, cn, "INSERT hl.Membership (MembershipId, PersonId, House, PeerageType, Party, Constituency, "
                    "StartDate, EndDate, StartReason, EndReason) VALUES (?,?,?,?,?,?,?,?,?,?)",
           members, [(W, 100, 0), (W, 100, 0), (V, 10, 0), (V, 4, 0), (W, 100, 0), (W, 200, 0),
                     (V, 10, 0), (V, 10, 0), (V, 50, 0), (V, 50, 0)])
    insert(cur, cn, "INSERT hl.PersonName (PersonId, Name) VALUES (?,?)", names, [(W, 100, 0), (W, 400, 0)])
    print(f"{len(names):,} name forms")
    if a.people_only:
        print("done: people reloaded. Now run sql/02_commons_link.sql")
        return

    sp_sql = ("INSERT hl.SourceSpeech (Gid, SittingDate, Seq, Location, ColNum, SpokenAt, SpeechClass, SpeakerName, "
              "PersonId, LordId, MajorHeading, MinorHeading, Body) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)")
    sp_sizes = [(V, 100, 0), (V, 10, 0), (B, 19, 0), (V, 10, 0), (V, 20, 0), (V, 10, 0), (V, 20, 0), (W, 400, 0),
                (W, 100, 0), (W, 100, 0), (W, 400, 0), (W, 400, 0), (W, 0, 0)]
    dv_sql = ("INSERT hl.Division (DivisionGid, SittingDate, DivNumber, Seq, MajorHeading, MinorHeading, Contents, "
              "NotContents) VALUES (?,?,?,?,?,?,?,?)")
    dv_sizes = [(V, 100, 0), (V, 10, 0), (pyodbc.SQL_INTEGER, 10, 0), (B, 19, 0), (W, 400, 0), (W, 400, 0),
                (pyodbc.SQL_INTEGER, 10, 0), (pyodbc.SQL_INTEGER, 10, 0)]
    vt_sql = "INSERT hl.Vote (DivisionGid, PersonId, LordId, PrintedName, Vote, Teller) VALUES (?,?,?,?,?,?)"
    vt_sizes = [(V, 100, 0), (W, 100, 0), (W, 100, 0), (W, 400, 0), (V, 20, 0), (pyodbc.SQL_BIT, 1, 0)]

    seen, t0, totals, bad = set(), time.time(), {"speech": 0, "division": 0, "vote": 0}, []
    for i, f in enumerate(files, 1):
        buf = {"speech": [], "division": [], "vote": []}
        try:
            for kind, r in parse_day(f):
                if kind in ("speech", "division"):
                    if r[0] in seen:
                        continue
                    seen.add(r[0])
                if kind == "speech" and not r[8] and r[9]:      # older files: lord id only
                    r = r[:8] + (lord_to_person.get(r[9]),) + r[9:]
                if kind == "vote" and not r[1] and r[2]:
                    r = (r[0], lord_to_person.get(r[2])) + r[2:]
                buf[kind].append(r)
        except ET.ParseError as e:
            bad.append((f, str(e)))
            continue
        totals["speech"] += insert(cur, cn, sp_sql, buf["speech"], sp_sizes)
        totals["division"] += insert(cur, cn, dv_sql, buf["division"], dv_sizes)
        totals["vote"] += insert(cur, cn, vt_sql, buf["vote"], vt_sizes)
        print(f"\r{i:,}/{len(files):,} days  {totals}  ({time.time() - t0:.0f}s)", end="", flush=True)
    print()
    for f, e in bad:
        print(f"skipped (bad XML): {f}: {e}")
    print(f"done: {totals}. Now run sql/01_lords_views.sql")


# ---------------------------------------------------------------- selftest

SAMPLE = """<?xml version="1.0" encoding="utf-8"?>
<publicwhip scrapeversion="a" latest="yes">
<major-heading id="uk.org.publicwhip/lords/2010-01-12a.1.0" nospeaker="true" colnum="1" time="15:00:00">Prayers</major-heading>
<speech id="uk.org.publicwhip/lords/2010-01-12a.1.1" nospeaker="true" colnum="1" time="15:00:00"><p pid="a1.1/1">Prayers&mdash;read by the Lord Bishop of Leicester.</p></speech>
<major-heading id="uk.org.publicwhip/lords/2010-01-12a.1.2" nospeaker="true" colnum="1">Schools: Music</major-heading>
<minor-heading id="uk.org.publicwhip/lords/2010-01-12a.1.3" nospeaker="true" colnum="1">Question</minor-heading>
<speech id="uk.org.publicwhip/lords/2010-01-12a.1.4" speakername="Lord Smith of Finsbury" person_id="uk.org.publicwhip/person/10544" colnum="1" time="15:06:00">
<p pid="a1.1/2">To ask Her Majesty&#8217;s Government&nbsp;what plans they have.</p><p pid="a1.1/3">Second paragraph.</p></speech>
<speech id="uk.org.publicwhip/lords/2010-01-12a.2.1" speakername="Noble Lords" nospeaker="true" colnum="2"><p>Order!</p></speech>
<speech id="uk.org.publicwhip/lords/2010-01-12a.2.2" speakername="Lord Old" speakerid="uk.org.publicwhip/lord/100001" colnum="2"><p>Older file style.</p></speech>
<division id="uk.org.publicwhip/lords/2010-01-12a.80.0" nospeaker="true" divdate="2010-01-12" divnumber="1" colnum="80">
<divisioncount content="200" not-content="150"/>
<lordlist vote="content"><lord person_id="uk.org.publicwhip/person/10544" vote="content" teller="yes">Smith of Finsbury, L.</lord></lordlist>
<lordlist vote="not-content"><lord id="uk.org.publicwhip/lord/100001" vote="not-content">Old, L.</lord></lordlist>
</division>
<speech id="uk.org.publicwhip/lords/2010-01-12a.GC1.1" speakername="The Deputy Chairman of Committees (Lord Geddes)" person_id="uk.org.publicwhip/person/13000" colnum="GC1"><p>Grand Committee.</p></speech>
<gidredirect oldgid="uk.org.publicwhip/lords/2010-01-12a.9.9" newgid="uk.org.publicwhip/lords/2010-01-12a.1.4" matchtype="altereddate"/>
</publicwhip>"""


def selftest():
    out = list(parse_day(SAMPLE, from_text=True))
    kinds = [k for k, _ in out]
    assert kinds == ["speech", "speech", "speech", "speech", "division", "vote", "vote", "speech"], kinds
    sp = [r for k, r in out if k == "speech"]
    assert sp[0][6] == "Procedural" and sp[0][10] == "Prayers" and "—" in sp[0][12]
    assert sp[1][7] == "Lord Smith of Finsbury" and sp[1][10] == "Schools: Music" and sp[1][11] == "Question"
    assert sp[1][12] == "To ask Her Majesty’s Government what plans they have.\nSecond paragraph.", sp[1][12]
    assert sp[2][7] == "Noble Lords" and sp[2][12] == "Order!"
    assert sp[3][8] is None and sp[3][9] == "uk.org.publicwhip/lord/100001"
    assert sp[4][3] == "GC" and sp[4][4] == "GC1" and sp[4][2] > sp[3][2]
    assert [r[2] for r in sp] == sorted(r[2] for r in sp)
    dv = next(r for k, r in out if k == "division")
    assert dv[2] == 1 and dv[6] == 200 and dv[7] == 150 and dv[4] == "Schools: Music"
    votes = [r for k, r in out if k == "vote"]
    assert votes[0][4] == "content" and votes[0][5] == 1 and votes[1][2] == "uk.org.publicwhip/lord/100001"
    assert latest_files(["daylord2010-01-12a.xml", "daylord2010-01-12b.xml", "daylord2009-01-01a.xml", "x.xml"],
                        2010, 2010) == ["daylord2010-01-12b.xml"]
    assert lords_name({"honorific_prefix": "Lord", "lordname": "Smith", "lordofname": "Finsbury"}) == "Lord Smith of Finsbury"
    assert lords_name({"honorific_prefix": "Bishop", "lordname": "", "lordofname": "Blackburn"}) == "Bishop of Blackburn"
    print("selftest passed")


if __name__ == "__main__":
    main()
