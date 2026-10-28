/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   04_matching_lessons.sql : how badly naive name matching goes wrong,
   measured on our own data. The sidebar to set against the Florida
   article: same problem, done with a second key and a refusal to guess.

   Three ways to link Odell's Commons speakers to people:
     A  naive      first name + surname, nothing else
     B  loose      surname only (what "fuzzy" usually turns into)
     C  ours       any known form of the name AND a Commons seat that
                   year, party as tie-break, otherwise leave it unlinked
   Run after 02_commons_link.sql (needs #names from it, same session,
   or it rebuilds it below).
   ===================================================================== */
USE [HANSARD];
GO

DROP TABLE IF EXISTS #n2, #a, #b;

SELECT DisplayAs, Yr = YEAR(SittingDate), FirstSpoke = MIN(SittingDate), LastSpoke = MAX(SittingDate),
       Speeches = COUNT(*), Surname = RIGHT(DisplayAs, CHARINDEX(N' ', REVERSE(DisplayAs) + N' ') - 1)
INTO #n2
FROM hc.SourceSpeech
WHERE DisplayAs IS NOT NULL AND DisplayAs NOT IN (N'Unknown', N'Several Hon. Members')
GROUP BY DisplayAs, YEAR(SittingDate);

-- A: exact given + surname, no dates
SELECT n.DisplayAs, n.Yr, n.Speeches, n.FirstSpoke, n.LastSpoke, p.PersonId
INTO #a
FROM #n2 AS n JOIN hl.Person AS p ON p.GivenName + N' ' + p.Surname = n.DisplayAs;

-- B: surname only, no dates
SELECT n.DisplayAs, n.Yr, n.Speeches, n.FirstSpoke, n.LastSpoke, p.PersonId
INTO #b
FROM #n2 AS n JOIN hl.Person AS p ON p.Surname = n.Surname;

/* For each method: how much it linked to exactly one person, how much
   it found nobody for, how much it found several for (a guess waiting
   to happen), and how many single links point at someone who wasn't
   even an MP that year (a link that is simply wrong). */
WITH m AS (
    SELECT Method = 'A naive', * FROM #a UNION ALL
    SELECT Method = 'B loose', * FROM #b UNION ALL
    SELECT Method = 'C ours', c.DisplayAs, c.Yr, n.Speeches, n.FirstSpoke, n.LastSpoke, c.PersonId
    FROM hl.CommonsName AS c JOIN #n2 AS n ON n.DisplayAs = c.DisplayAs AND n.Yr = c.Yr
),
per AS (
    SELECT Method, DisplayAs, Yr, Speeches = MAX(Speeches), Cands = COUNT(DISTINCT PersonId),
           PersonId = MIN(PersonId), FirstSpoke = MIN(FirstSpoke), LastSpoke = MAX(LastSpoke)
    FROM m GROUP BY Method, DisplayAs, Yr
),
flagged AS (
    SELECT per.*, Wrong = CASE WHEN per.Cands = 1 AND NOT EXISTS (
                      SELECT 1 FROM hl.Membership AS ms
                      WHERE ms.PersonId = per.PersonId AND ms.House = 'Commons'
                        AND ISNULL(ms.StartDate, '1900-01-01') <= per.LastSpoke
                        AND ISNULL(ms.EndDate, '9999-12-31') >= per.FirstSpoke) THEN 1 ELSE 0 END
    FROM per
)
SELECT f.Method,
       LinkedPct    = CAST(100.0 * SUM(CASE WHEN f.Cands = 1 AND f.Wrong = 0 THEN f.Speeches ELSE 0 END) / t.Total AS decimal(5,2)),
       WrongPct     = CAST(100.0 * SUM(CASE WHEN f.Wrong = 1 THEN f.Speeches ELSE 0 END) / t.Total AS decimal(5,2)),
       AmbiguousPct = CAST(100.0 * SUM(CASE WHEN f.Cands > 1 THEN f.Speeches ELSE 0 END) / t.Total AS decimal(5,2)),
       NoMatchPct   = CAST(100.0 * (t.Total - SUM(f.Speeches)) / t.Total AS decimal(5,2))
FROM flagged AS f CROSS JOIN (SELECT Total = SUM(Speeches) FROM #n2) AS t
GROUP BY f.Method, t.Total
ORDER BY f.Method;

-- The cautionary tales: names the naive method pins on the wrong person
SELECT TOP (25) a.DisplayAs, a.Yr, a.Speeches, NaiveGaveTo = pn.DisplayName, OursGaveTo = po.DisplayName
FROM #a AS a
JOIN hl.Person AS pn ON pn.PersonId = a.PersonId
LEFT JOIN hl.CommonsName AS c ON c.DisplayAs = a.DisplayAs AND c.Yr = a.Yr
LEFT JOIN hl.Person AS po ON po.PersonId = c.PersonId
WHERE c.PersonId IS NULL OR c.PersonId <> a.PersonId
ORDER BY a.Speeches DESC;
GO
