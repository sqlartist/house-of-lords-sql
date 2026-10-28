/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   02_commons_link.sql : tie Odell's Commons speakers to ParlParse people.

   hc.SourceSpeech.PersonId came through empty, so the link is made on
   the name. Odell's DisplayAs uses formal first names ('Antony Newton',
   'Jeremy Ashdown', 'Charles Jenkin'), so it is matched against every
   form in hl.PersonName: given, formal and nicknames, each family
   name the person has had. A match only counts if that person held a
   Commons seat in that year, and the link is made year by year, so
   the two John Smiths of 1979-2009 split correctly. Where two people
   still fit, the one in the speaker's party wins; if that doesn't
   settle it, the year is left unlinked rather than guessed.

   Needs hl.PersonName (rerun 00_lords_schema.sql, then
   python load_lords.py --people-only ...). Run after 01_lords_views.sql.
   ===================================================================== */
USE [HANSARD];
GO

DROP TABLE IF EXISTS hl.CommonsName;
CREATE TABLE hl.CommonsName
(
    DisplayAs  nvarchar(400) NOT NULL,
    Yr         int           NOT NULL,
    PersonId   nvarchar(100) NOT NULL,
    Speeches   int           NOT NULL,
    PRIMARY KEY (DisplayAs, Yr),
    INDEX ix_person (PersonId)
);
GO

DROP TABLE IF EXISTS #names, #cand;

SELECT DisplayAs, Yr = YEAR(SittingDate),
       Clean = TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(DisplayAs,
                    N'The Reverend ', N''), N'The Rev ', N''), N'Sir ', N''), N'Dr ', N''), N'Dame ', N''), N'Hon ', N''), N'Lady ', N'')),
       Party = MAX(Party), FirstSpoke = MIN(SittingDate), LastSpoke = MAX(SittingDate), Speeches = COUNT(*)
INTO #names
FROM hc.SourceSpeech
WHERE DisplayAs IS NOT NULL AND DisplayAs NOT IN (N'Unknown', N'Several Hon. Members')
GROUP BY DisplayAs, YEAR(SittingDate);

SELECT n.DisplayAs, n.Yr, pn.PersonId,
       PartyFit = MAX(CASE WHEN REPLACE(LOWER(n.Party), N' ', N'-') = m.Party THEN 1 ELSE 0 END)
INTO #cand
FROM #names AS n
JOIN hl.PersonName AS pn ON pn.Name = n.Clean
JOIN hl.Membership AS m
  ON m.PersonId = pn.PersonId AND m.House = 'Commons'
 AND ISNULL(m.StartDate, '1900-01-01') <= n.LastSpoke
 AND ISNULL(m.EndDate,   '9999-12-31') >= n.FirstSpoke
GROUP BY n.DisplayAs, n.Yr, pn.PersonId;

WITH r AS (SELECT c.*, Cands = COUNT(*) OVER (PARTITION BY c.DisplayAs, c.Yr),
                       Fits  = SUM(c.PartyFit) OVER (PARTITION BY c.DisplayAs, c.Yr)
           FROM #cand AS c)
INSERT hl.CommonsName (DisplayAs, Yr, PersonId, Speeches)
SELECT r.DisplayAs, r.Yr, r.PersonId, n.Speeches
FROM r JOIN #names AS n ON n.DisplayAs = r.DisplayAs AND n.Yr = r.Yr
WHERE r.Cands = 1 OR (r.PartyFit = 1 AND r.Fits = 1);
GO

-- How much of the Commons got linked ('Unknown' and 'Several Hon. Members' left out)
SELECT NameYears = (SELECT COUNT(*) FROM #names),
       Linked    = (SELECT COUNT(*) FROM hl.CommonsName),
       SpeechPct = CAST(100.0 * (SELECT SUM(Speeches) FROM hl.CommonsName)
                        / (SELECT SUM(Speeches) FROM #names) AS decimal(5,2));

-- The biggest names left unlinked, with how many people fitted
SELECT TOP (40) n.DisplayAs, FirstSpoke = MIN(n.FirstSpoke), LastSpoke = MAX(n.LastSpoke), Speeches = SUM(n.Speeches),
       MaxCandidates = MAX(ISNULL(k.Cands, 0))
FROM #names AS n
OUTER APPLY (SELECT Cands = COUNT(*) FROM #cand AS c WHERE c.DisplayAs = n.DisplayAs AND c.Yr = n.Yr) AS k
WHERE NOT EXISTS (SELECT 1 FROM hl.CommonsName AS l WHERE l.DisplayAs = n.DisplayAs AND l.Yr = n.Yr)
GROUP BY n.DisplayAs
ORDER BY Speeches DESC;

-- Query 5 again, now joined properly: MPs who became peers, speeches in each House
SELECT TOP (50) p.DisplayName, p.CommonsFrom, p.CommonsTo, p.FirstSat,
       CommonsSpeeches = ISNULL((SELECT SUM(Speeches) FROM hl.CommonsName AS c WHERE c.PersonId = p.PersonId), 0),
       LordsSpeeches   = (SELECT COUNT(*) FROM hl.SourceSpeech AS s
                          WHERE s.PersonId = p.PersonId AND s.SpeechClass = 'Speech')
FROM hl.vPeer AS p
WHERE p.ExMP = 1
ORDER BY LordsSpeeches DESC;
GO
