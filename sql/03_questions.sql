/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   03_questions.sql : the article's questions, one block each.
   Run after 01 and 02, with the full 1999-on load in place.

   Q1  How many hereditary peers, year by year? Who came back as life peers?
   Q2  Do peers give up their seats? (retire, resign, die, excluded)
   Q3  Do they vote with their party? Rebellion rates and top rebels
   Q4  "Send him upstairs": how fast do MPs land in the Lords?
   Q5  Is there any bitching? Shouts from the floor, against the Commons
   Q6  What power do they have? Government defeats in the Lords
   Q7  Best, worst, pointless: work rate per peer
   ===================================================================== */
USE [HANSARD];
GO

/* Who was in government, for Q3 and Q6. Party ids as in people.json. */
DROP TABLE IF EXISTS hl.Government;
CREATE TABLE hl.Government (FromDate date NOT NULL, ToDate date NULL, Party nvarchar(100) NOT NULL);
INSERT hl.Government VALUES
    ('1997-05-02', '2010-05-11', N'labour'),
    ('2010-05-11', '2015-05-08', N'conservative'),
    ('2010-05-11', '2015-05-08', N'liberal-democrat'),
    ('2015-05-08', '2024-07-05', N'conservative'),
    ('2024-07-05', NULL,         N'labour');
GO

/* One row per vote, with the voter's party and peerage on the day */
DROP TABLE IF EXISTS #v;
SELECT DISTINCT v.DivisionGid, d.SittingDate, v.PersonId, v.Vote, seat.Party, seat.PeerageType,
       InGov = CASE WHEN EXISTS (SELECT 1 FROM hl.Government AS g
                                 WHERE g.Party = seat.Party AND d.SittingDate >= g.FromDate
                                   AND (g.ToDate IS NULL OR d.SittingDate < g.ToDate)) THEN 1 ELSE 0 END
INTO #v
FROM hl.Vote AS v
JOIN hl.Division AS d ON d.DivisionGid = v.DivisionGid
OUTER APPLY hl.fnSeatOn(v.PersonId, d.SittingDate) AS seat
WHERE v.PersonId IS NOT NULL;
GO

/* ---------------------------------------------------------------------
   Q1  Hereditary peers, a snapshot on 1 July each year.
   people.json starts in 1999, so the 600-odd removed that November are
   not in it: the 1999 row is the 92 who stayed (plus any who left
   later). The 2026 Act shows up as the April 2026 exits.
   --------------------------------------------------------------------- */
WITH yrs AS (SELECT Yr = 1999 + n
             FROM (SELECT TOP (28) n = ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 FROM sys.all_objects) AS t)
SELECT y.Yr,
       Hereditary = COUNT(DISTINCT CASE WHEN m.PeerageType IN ('HP','HD','HO') THEN m.PersonId END),
       Life       = COUNT(DISTINCT CASE WHEN m.PeerageType = 'L' THEN m.PersonId END),
       Bishops    = COUNT(DISTINCT CASE WHEN m.PeerageType = 'B' THEN m.PersonId END),
       LawLords   = COUNT(DISTINCT CASE WHEN m.PeerageType = 'A' THEN m.PersonId END)
FROM yrs AS y
JOIN hl.Membership AS m
  ON m.House = 'Lords'
 AND ISNULL(m.StartDate, '1900-01-01') <= DATEFROMPARTS(y.Yr, 7, 1)
 AND ISNULL(m.EndDate,   '9999-12-31') >= DATEFROMPARTS(y.Yr, 7, 1)
GROUP BY y.Yr ORDER BY y.Yr;

-- Hereditary peers who came back with a life peerage (1999 and 2026 both did this)
SELECT p.DisplayName, HereditaryParty = h.Party, HereditaryUntil = h.EndDate,
       LifePeerFrom = l.StartDate, LifeParty = l.Party
FROM hl.Membership AS h
JOIN hl.Membership AS l ON l.PersonId = h.PersonId AND l.House = 'Lords' AND l.PeerageType = 'L'
                       AND l.StartDate >= h.EndDate
JOIN hl.Person AS p ON p.PersonId = h.PersonId
WHERE h.PeerageType IN ('HP','HD','HO')
ORDER BY h.EndDate, p.DisplayName;
GO

/* ---------------------------------------------------------------------
   Q2  How peers leave. 'retired' and 'resigned' only exist after the
   2014 Act. A NULL reason is mostly the 2026 hereditary exclusion.
   Tony Benn disclaimed his peerage in 1963, so he isn't in this data.
   --------------------------------------------------------------------- */
SELECT Yr = YEAR(m.EndDate), Reason = ISNULL(m.EndReason, 'excluded/other'), m.PeerageType, N = COUNT(*)
FROM hl.Membership AS m
WHERE m.House = 'Lords' AND m.EndDate IS NOT NULL AND ISNULL(m.EndReason, '') <> 'changed_party'
  AND NOT EXISTS (SELECT 1 FROM hl.Membership AS n           -- a new seat straight after = not really leaving
                  WHERE n.PersonId = m.PersonId AND n.House = 'Lords' AND n.StartDate BETWEEN m.EndDate AND DATEADD(day, 1, m.EndDate))
GROUP BY YEAR(m.EndDate), ISNULL(m.EndReason, 'excluded/other'), m.PeerageType
ORDER BY Yr, N DESC;

-- Party switchers, and which way they went
SELECT p.DisplayName, Switched = m.EndDate, FromParty = m.Party, ToParty = n.Party
FROM hl.Membership AS m
JOIN hl.Membership AS n ON n.PersonId = m.PersonId AND n.House = 'Lords' AND n.StartDate BETWEEN m.EndDate AND DATEADD(day, 1, m.EndDate)
JOIN hl.Person AS p ON p.PersonId = m.PersonId
WHERE m.House = 'Lords' AND m.EndReason = 'changed_party'
ORDER BY m.EndDate;
GO

/* ---------------------------------------------------------------------
   Q3  Voting with the party. The party line in a division is how most
   of that party voted (ties dropped, and at least 5 of them voting).
   A rebel vote is one cast the other way. Crossbenchers and bishops
   have no whip, so they get a cohesion figure instead.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #line;
SELECT DivisionGid, Party, N = COUNT(*),
       Line = CASE WHEN SUM(CASE WHEN Vote = 'content' THEN 1 ELSE 0 END)
                      > SUM(CASE WHEN Vote = 'not-content' THEN 1 ELSE 0 END) THEN 'content' ELSE 'not-content' END,
       Share = 1.0 * ABS(SUM(CASE WHEN Vote = 'content' THEN 1 ELSE -1 END)) / COUNT(*)
INTO #line
FROM #v WHERE Party IS NOT NULL
GROUP BY DivisionGid, Party
HAVING COUNT(*) >= 5
   AND SUM(CASE WHEN Vote = 'content' THEN 1 ELSE 0 END) <> SUM(CASE WHEN Vote = 'not-content' THEN 1 ELSE 0 END);

-- Rebellion rate by party, split by whether they were in government
SELECT v.Party, InGovernment = v.InGov, Votes = COUNT(*),
       Rebel = SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END),
       RebelPct = CAST(100.0 * SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2)),
       AvgCohesion = CAST(AVG(l.Share) AS decimal(4,3))   -- 1.0 = whole party the same way
FROM #v AS v JOIN #line AS l ON l.DivisionGid = v.DivisionGid AND l.Party = v.Party
GROUP BY v.Party, v.InGov
HAVING COUNT(*) >= 1000
ORDER BY Votes DESC;

-- Does the route in change it? Hereditary vs life vs ex-MP, within the whipped parties
SELECT Route = CASE WHEN pr.ExMP = 1 THEN 'ex-MP' WHEN v.PeerageType IN ('HP','HD','HO') THEN 'hereditary' ELSE 'life' END,
       Votes = COUNT(*),
       RebelPct = CAST(100.0 * SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2))
FROM #v AS v
JOIN #line AS l ON l.DivisionGid = v.DivisionGid AND l.Party = v.Party
JOIN hl.vPeer AS pr ON pr.PersonId = v.PersonId
WHERE v.Party IN (N'labour', N'conservative', N'liberal-democrat')
GROUP BY CASE WHEN pr.ExMP = 1 THEN 'ex-MP' WHEN v.PeerageType IN ('HP','HD','HO') THEN 'hereditary' ELSE 'life' END;

-- The serial rebels (at least 200 whipped votes)
SELECT TOP (30) p.DisplayName, v.Party, Votes = COUNT(*),
       Rebel = SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END),
       RebelPct = CAST(100.0 * SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2))
FROM #v AS v
JOIN #line AS l ON l.DivisionGid = v.DivisionGid AND l.Party = v.Party
JOIN hl.Person AS p ON p.PersonId = v.PersonId
WHERE v.Party IN (N'labour', N'conservative', N'liberal-democrat')
GROUP BY p.DisplayName, v.Party
HAVING COUNT(*) >= 200
ORDER BY RebelPct DESC;
GO

/* ---------------------------------------------------------------------
   Q4  "Send him upstairs". Gap from leaving the Commons to entering
   the Lords, and how they left: lost their seat (general_election_
   standing), stood down, or the seat ended at a general election.
   Earlier Commons careers are in people.json back to 1918, so this
   covers peers made after 1999 whatever their Commons era.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #up;
SELECT p.PersonId, p.DisplayName, p.CommonsTo, p.FirstSat,
       HowLeft = (SELECT TOP (1) EndReason FROM hl.Membership AS m
                  WHERE m.PersonId = p.PersonId AND m.House = 'Commons' ORDER BY m.EndDate DESC),
       GapDays = DATEDIFF(day, p.CommonsTo, p.FirstSat),
       FirstParty = (SELECT TOP (1) Party FROM hl.Membership AS m
                     WHERE m.PersonId = p.PersonId AND m.House = 'Lords' ORDER BY m.StartDate)
INTO #up
FROM hl.vPeer AS p
WHERE p.ExMP = 1 AND p.FirstSat > p.CommonsTo;

SELECT Gap = CASE WHEN GapDays <= 90 THEN '1: within 3 months' WHEN GapDays <= 365 THEN '2: within a year'
                  WHEN GapDays <= 365 * 5 THEN '3: 1-5 years' ELSE '4: over 5 years' END,
       Peers = COUNT(*),
       LostSeat = SUM(CASE WHEN HowLeft = 'general_election_standing' THEN 1 ELSE 0 END)
FROM #up
GROUP BY CASE WHEN GapDays <= 90 THEN '1: within 3 months' WHEN GapDays <= 365 THEN '2: within a year'
              WHEN GapDays <= 365 * 5 THEN '3: 1-5 years' ELSE '4: over 5 years' END
ORDER BY Gap;

-- The ones who lost their seat and were in ermine fastest
SELECT TOP (30) DisplayName, FirstParty, CommonsTo, FirstSat, GapDays, HowLeft
FROM #up WHERE HowLeft = 'general_election_standing'
ORDER BY GapDays;
GO

/* ---------------------------------------------------------------------
   Q5  Bitching. Hansard rarely records Lords heckling, but it does
   file collective shouts under "Noble Lords" / "A noble Lord". Rate
   per 1,000 peer speeches per year, and what they shout. The Commons
   comparison uses Odell's 'Hon. Members' rows the same way.
   --------------------------------------------------------------------- */
SELECT Yr = YEAR(SittingDate),
       Speeches = SUM(CASE WHEN PersonId IS NOT NULL THEN 1 ELSE 0 END),
       Shouts   = SUM(CASE WHEN SpeakerName IN (N'Noble Lords', N'A noble Lord') THEN 1 ELSE 0 END),
       PerK     = CAST(1000.0 * SUM(CASE WHEN SpeakerName IN (N'Noble Lords', N'A noble Lord') THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CASE WHEN PersonId IS NOT NULL THEN 1 ELSE 0 END), 0) AS decimal(6,2)),
       OrderCalls = SUM(CASE WHEN SpeakerName IN (N'Noble Lords', N'A noble Lord') AND Body LIKE N'%Order%' THEN 1 ELSE 0 END)
FROM hl.SourceSpeech
WHERE SpeechClass = 'Speech'
GROUP BY YEAR(SittingDate) ORDER BY Yr;

SELECT TOP (25) Shout = LEFT(Body, 60), N = COUNT(*)
FROM hl.SourceSpeech
WHERE SpeakerName IN (N'Noble Lords', N'A noble Lord')
GROUP BY LEFT(Body, 60) ORDER BY N DESC;

-- Commons, same measure, same years (1999-2021)
SELECT Yr = YEAR(SittingDate),
       PerK = CAST(1000.0 * SUM(CASE WHEN SpeakerName LIKE N'Hon. Member%' OR SpeakerName LIKE N'An hon. Member%' THEN 1 ELSE 0 END)
                   / NULLIF(SUM(CASE WHEN DisplayAs IS NOT NULL THEN 1 ELSE 0 END), 0) AS decimal(6,2))
FROM hc.SourceSpeech
WHERE SittingDate >= '1999-11-01'
GROUP BY YEAR(SittingDate) ORDER BY Yr;
GO

/* ---------------------------------------------------------------------
   Q6  Power. The Lords can't block money bills and can only delay
   others, but they can defeat the government and send bills back.
   A government defeat: the government parties' peers mostly voted one
   way and the House went the other. Contents > Not-Contents = carried.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #gov;
SELECT v.DivisionGid,
       GovSide = CASE WHEN SUM(CASE WHEN v.Vote = 'content' THEN 1 ELSE 0 END)
                         > SUM(CASE WHEN v.Vote = 'not-content' THEN 1 ELSE 0 END) THEN 'content' ELSE 'not-content' END
INTO #gov
FROM #v AS v WHERE v.InGov = 1
GROUP BY v.DivisionGid
HAVING COUNT(*) >= 5;

SELECT Yr = YEAR(d.SittingDate), Divisions = COUNT(*),
       GovDefeats = SUM(CASE WHEN g.GovSide <> CASE WHEN d.Contents > d.NotContents THEN 'content' ELSE 'not-content' END
                             THEN 1 ELSE 0 END),
       DefeatPct = CAST(100.0 * SUM(CASE WHEN g.GovSide <> CASE WHEN d.Contents > d.NotContents THEN 'content' ELSE 'not-content' END
                                         THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,1))
FROM hl.Division AS d JOIN #gov AS g ON g.DivisionGid = d.DivisionGid
GROUP BY YEAR(d.SittingDate) ORDER BY Yr;

-- The biggest defeats, with what they were about
SELECT TOP (25) d.SittingDate, d.MajorHeading, d.MinorHeading, d.Contents, d.NotContents,
       Margin = ABS(d.Contents - d.NotContents)
FROM hl.Division AS d JOIN #gov AS g ON g.DivisionGid = d.DivisionGid
WHERE g.GovSide <> CASE WHEN d.Contents > d.NotContents THEN 'content' ELSE 'not-content' END
ORDER BY Margin DESC;
GO

/* ---------------------------------------------------------------------
   Q7  Best, worst, pointless. Hansard can't judge quality, but it can
   measure work. Per peer: years in the House (in this data), speeches,
   divisions voted in, and both per year. "Pointless" here means five
   or more years in the House with almost nothing on the record.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #work;
SELECT p.PersonId, p.DisplayName, p.PeerageType, p.FirstSat, p.LastSat, p.ExMP,
       Years = DATEDIFF(day, CASE WHEN p.FirstSat < '1999-11-11' THEN '1999-11-11' ELSE p.FirstSat END,
                        ISNULL(p.LastSat, CAST(GETDATE() AS date))) / 365.25,
       Speeches = (SELECT COUNT(*) FROM hl.SourceSpeech AS s WHERE s.PersonId = p.PersonId AND s.SpeechClass = 'Speech'),
       Votes    = (SELECT COUNT(DISTINCT v.DivisionGid) FROM hl.Vote AS v WHERE v.PersonId = p.PersonId)
INTO #work
FROM hl.vPeer AS p;

-- Most active (per year in the House, at least 3 years)
SELECT TOP (25) DisplayName, PeerageType, Years = CAST(Years AS decimal(4,1)), Speeches, Votes,
       SpeechesPerYr = CAST(Speeches / NULLIF(Years, 0) AS decimal(7,1)), VotesPerYr = CAST(Votes / NULLIF(Years, 0) AS decimal(7,1))
FROM #work WHERE Years >= 3 ORDER BY Speeches / NULLIF(Years, 0) DESC;

-- Pointless: 5+ years, fewer than one speech and five votes a year
SELECT DisplayName, PeerageType, FirstSat, LastSat, Years = CAST(Years AS decimal(4,1)), Speeches, Votes
FROM #work
WHERE Years >= 5 AND Speeches < Years AND Votes < 5 * Years
ORDER BY Speeches + Votes, Years DESC;

-- Pointless, by route in
SELECT PeerageType, ExMP, Peers = COUNT(*),
       Silent = SUM(CASE WHEN Years >= 5 AND Speeches < Years AND Votes < 5 * Years THEN 1 ELSE 0 END)
FROM #work WHERE Years >= 5
GROUP BY PeerageType, ExMP ORDER BY PeerageType, ExMP;
GO

/* ---------------------------------------------------------------------
   Q3b  Do peers mellow? Rebellion rate by how long they'd been in the
   House when they voted, for the whipped parties. If the Lords softens
   party politics, the rate should climb with years served. Ex-MPs are
   split out: they arrive after a career of being whipped.
   Needs #v and #line from Q3 (same session).
   --------------------------------------------------------------------- */
SELECT Tenure = CASE WHEN t.Yrs < 2 THEN '1: first 2 years' WHEN t.Yrs < 5 THEN '2: 2-5 years'
                     WHEN t.Yrs < 10 THEN '3: 5-10 years' ELSE '4: 10+ years' END,
       pr.ExMP, Votes = COUNT(*),
       RebelPct = CAST(100.0 * SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2))
FROM #v AS v
JOIN #line AS l ON l.DivisionGid = v.DivisionGid AND l.Party = v.Party
JOIN hl.vPeer AS pr ON pr.PersonId = v.PersonId
CROSS APPLY (SELECT Yrs = DATEDIFF(day, pr.FirstSat, v.SittingDate) / 365.25) AS t
WHERE v.Party IN (N'labour', N'conservative', N'liberal-democrat')
GROUP BY CASE WHEN t.Yrs < 2 THEN '1: first 2 years' WHEN t.Yrs < 5 THEN '2: 2-5 years'
              WHEN t.Yrs < 10 THEN '3: 5-10 years' ELSE '4: 10+ years' END, pr.ExMP
ORDER BY pr.ExMP, Tenure;

-- Is the House getting more tribal? Average party cohesion per year (1.0 = every party votes as a block)
SELECT Yr = YEAR(d.SittingDate), l.Party, Divisions = COUNT(*), AvgCohesion = CAST(AVG(l.Share) AS decimal(4,3))
FROM #line AS l JOIN hl.Division AS d ON d.DivisionGid = l.DivisionGid
WHERE l.Party IN (N'labour', N'conservative', N'liberal-democrat', N'crossbench')
GROUP BY YEAR(d.SittingDate), l.Party
ORDER BY l.Party, Yr;
GO
