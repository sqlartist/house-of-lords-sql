"""Parse the downloaded files without a server and report what would load."""
import collections, glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import load_lords as L

folder = sys.argv[1] if len(sys.argv) > 1 else "_no_upload/lords_xml"
files = L.latest_files(os.listdir(folder), 1999, 2100)
_, _, lord_to_person = L.load_people(os.path.join(folder, "people.json"))
n = collections.Counter(); nomatch = collections.Counter(); names = collections.Counter(); bad = []
sample = None
for f in files:
    try:
        for kind, r in L.parse_day(os.path.join(folder, f)):
            n[kind] += 1
            if kind == "speech":
                n[r[3]] += 1
                pid = r[8] or lord_to_person.get(r[9])
                if r[6] == "Speech" and not pid:
                    nomatch[r[7]] += 1
                if r[6] == "Speech" and pid:
                    n["speech_matched"] += 1
                if sample is None and r[12] and "£" in r[12]:
                    sample = r[12][:200]
            if kind == "vote":
                if not (r[1] or lord_to_person.get(r[2])):
                    n["vote_unmatched"] += 1
    except Exception as e:
        bad.append((f, repr(e)))
print(len(files), "files", dict(n))
print("bad:", bad[:5])
print("speeches with no person, top 15:", nomatch.most_common(15))
print("pound sample:", sample)
