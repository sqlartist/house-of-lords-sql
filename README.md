# House of Lords: slice 2 of the Hansard series

This follows *Two Graphics Cards and 1.7 Million Speeches*, *Nobody Laughed at Margaret Thatcher* and *Order! Order!*. Those cover the Commons, using Odell's *Hansard Speeches 1979–2021*. This adds the Lords from 1999 onwards, from the TheyWorkForYou / ParlParse daily XML plus ParlParse `people.json`. It then joins the two Houses on the person, so an MP who became a peer is one `PersonId` in both.

Everything goes into the existing `HANSARD` database under a new `hl` schema. Nothing in `hc` or `dbo` is changed.

## Layout

| Folder | What's in it |
| --- | --- |
| `sql/` | Eight scripts, run in order (below) |
| `python/` | `load_lords.py`, the loader, and `check_parse.py`, which tests the parse without a server |
| `graphics/` | `chamber_swingometer.html`, the animated chamber |


## The scripts

| File | What it does | Needs |
| --- | --- | --- |
| `sql/00_lords_schema.sql` | Creates `hl.SourceSpeech`, `hl.Person`, `hl.Membership`, `hl.PersonName`, `hl.Division` and `hl.Vote` | |
| `python/load_lords.py` | Downloads and loads the XML and people.json | 00 |
| `sql/01_lords_views.sql` | `hl.fnSeatOn`, `hl.vPeer` and `hl.vSpeech` (each speech with the peer's party and type on the day), plus six first-look queries | the load |
| `sql/02_commons_link.sql` | `hl.CommonsName`, which links Odell's Commons speaker names to people by any name form, plus a seat that year, plus party. It refuses to guess when unsure (97.8% linked) | 01 |
| `sql/03_questions.sql` | Hereditary numbers, how peers leave, rebellion, "send him upstairs", heckling, government defeats, and best, worst and pointless peers | 02 |
| `sql/04_matching_lessons.sql` | Naive and loose name matching against ours: the Florida sidebar | 02 |
| `sql/05_new_angles.sql` | Stephen Benn, Benn in the Lords, sitcoms, rebuked-then-rewarded, who the Lords shouts at, and ermine voice | 02, the hypercube (`hc.Speech`, `hc.ChairFlag`) |
| `sql/06_chamber.sql` | The Commons chamber at every election since 1979, in SQL Spatial and SVG | 02 |
| `sql/07_out_of_place.sql` | The coded-message test: speeches far from their own debate, in embedding space | the first article's `dbo.speech`, `dbo.speech_vec`, `dbo.speech_sig`, `dbo.centroid` and `dbo.speech_role` |

## Runbook

```
-- SSMS: sql/00_lords_schema.sql
pip install pyodbc requests
python python/load_lords.py --selftest
python python/load_lords.py --sql "Driver={ODBC Driver 18 for SQL Server};Server=.;Database=HANSARD;Trusted_Connection=yes;TrustServerCertificate=yes"
-- SSMS: sql/01 to sql/07, in order
```

Run the loader from this folder. It downloads into `_no_upload/lords_xml` (or pass `--folder`), and only downloads once. Useful flags:
- `--from 2010 --to 2015` loads only those years
- `--no-download` uses the files already there
- `--parse-only` counts without a server
- `--people-only` reloads just the people tables

theyworkforyou.com may be blocked on some networks, so run the download on a normal connection. Alternatively, fetch with `rsync -az data.theyworkforyou.com::parldata/scrapedxml/lordspages/ _no_upload/lords_xml/` and then run with `--no-download`.

**Slow ones:**
- 05 section C (the sitcoms) checks every speech in both Houses against every pattern.
- 07 compares speeches within each debate.

Both take a while. Everything else runs in seconds or minutes.

You'll need SQL Server 2025 for `VECTOR_DISTANCE` in 07, and SQL Server 2022 or later for `LAG … IGNORE NULLS` in 05.

## Caveats

- **The data starts in 1999.** Lords data begins in November 1999. Anything earlier is on the Millbank historic Hansard site and would need a separate scraper.
- **Odell's `PersonId` is empty.** That's why 02 links the Houses by name and seat.
- **Collations differ.** `hc.SourceSpeech` is `Latin1_General_100_CI_AS_SC_UTF8`, while `hl` and tempdb use the server default. Comparisons across the two need an explicit `COLLATE`.
- **Chair speeches are filed under the person's own name** in the Lords, and sometimes for Commons deputies too. 07 filters them out with `dbo.speech_role` plus text patterns.
- **Some people are split into two records** in people.json (for example Michael Morris and Lord Naseby, or Quintin Hogg and Lord Hailsham). Former-MP counts are a floor.
- **people.json rarely records that an MP lost their seat.** Use election results for that.
- **2016–18 interjection counts collapse in both Houses.** That's a recording artefact, so leave those years out of anything that counts shouts.
- **Grand Committee isn't in the daily files.**
- **The 1994-04-15 Merchant Shipping debate appears twice in `dbo.speech`.** 07 removes the duplicates.
