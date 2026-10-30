/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   08_spitting_image.sql : does the Commons get noisier the day after
   Spitting Image?

   The show ran on ITV, almost always on Sunday nights, from February
   1984 to February 1996. If it changed the mood of the House, the
   first sitting day after a broadcast (usually the Monday) should be
   rowdier than a Monday when it wasn't on.

   Three measures per sitting day, all from the Order! Order! tables:
     Chair     every intervention flagged in hc.ChairFlag, per 1,000
               speeches, and each Category separately (SEAT, WITHDRAW,
               NAME, NOISE and the rest, whatever 01 defined)
     Shouts    collective interjections ("Hon. Members: ...")
   Compared:
     A  the day after a new episode vs other days, same weekday,
        same years, so Mondays are only ever compared with Mondays
     B  the placebo: the same test with every broadcast date moved
        26 weeks (still a Sunday, but a week the show wasn't on).
        If B shows the same "effect" as A, A isn't about the show.
     C  the puppets: shouts aimed at well-known Spitting Image targets
        in the three sitting days after a broadcast vs other days

   Broadcast dates: British Comedy Guide episode guides
   (comedy.co.uk/tv/spitting_image/episodes/1 to 20), fetched October
   2026. Compilations and repeats are kept but not used in the test.
   Needs: hc.Speech, hc.SourceSpeech, hc.ChairFlag (Order! Order!).
   ===================================================================== */
USE [HANSARD];
GO

/* ---------------------------------------------------------------------
   0. The broadcast dates
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS hl.SpittingImage;
CREATE TABLE hl.SpittingImage
(
    AirDate  date         NOT NULL PRIMARY KEY,
    Series   varchar(10)  NOT NULL,     -- as numbered by comedy.co.uk
    Episode  varchar(20)  NOT NULL,
    Kind     varchar(10)  NOT NULL,     -- new | special | repeat
    Title    nvarchar(200) NULL
);

INSERT hl.SpittingImage (AirDate, Series, Episode, Kind, Title) VALUES
-- Series 1, 1984
('1984-02-26','1','1','new',NULL),('1984-03-04','1','2','new',NULL),
('1984-03-18','1','3','new',NULL),('1984-04-01','1','4','new',NULL),
('1984-04-08','1','5','new',NULL),('1984-04-15','1','6','new',NULL),
('1984-05-13','1','7','new',NULL),('1984-05-20','1','8','new',NULL),
('1984-05-27','1','9','new',NULL),('1984-06-03','1','10','new',NULL),
('1984-06-10','1','11','new',NULL),('1984-06-17','1','12','new',NULL),
('1984-12-29','1','H','repeat',N'The Very Beast Of Spitting Image'),
-- Series 2, 1985
('1985-01-06','2','1','new',NULL),('1985-01-13','2','2','new',NULL),
('1985-01-20','2','3','new',NULL),('1985-01-27','2','4','new',NULL),
('1985-02-03','2','5','new',NULL),('1985-02-10','2','6','new',NULL),
('1985-02-24','2','7','new',NULL),('1985-03-03','2','8','new',NULL),
('1985-03-10','2','9','new',NULL),('1985-03-17','2','10','new',NULL),
('1985-03-24','2','11','new',NULL),
('1985-12-28','2','H','repeat',N'The Second Beast of Spitting Image'),
-- Series 3 to 5, 1986
('1986-01-05','3','1','new',NULL),('1986-01-12','3','2','new',NULL),
('1986-01-19','3','3','new',NULL),('1986-01-26','3','4','new',NULL),
('1986-02-02','3','5','new',NULL),
('1986-03-30','4','1','new',NULL),('1986-04-06','4','2','new',NULL),
('1986-04-13','4','3','new',NULL),('1986-04-20','4','4','new',NULL),
('1986-04-27','4','5','new',NULL),('1986-05-04','4','6','new',NULL),
('1986-09-14','Sp','1','special',N'Down And Out In The White House'),
('1986-09-28','5','1','new',NULL),('1986-10-05','5','2','new',NULL),
('1986-10-12','5','3','new',NULL),('1986-10-19','5','4','new',NULL),
('1986-10-26','5','5','new',NULL),('1986-11-02','5','6','new',NULL),
-- Series 6, 1987
('1987-11-01','6','1','new',NULL),('1987-11-08','6','2','new',NULL),
('1987-11-15','6','3','new',NULL),('1987-11-22','6','4','new',NULL),
('1987-11-29','6','5','new',NULL),('1987-12-06','6','6','new',NULL),
('1987-12-27','6','Xmas','special',N'Holiday Special'),
-- 1988: specials, then series 7
('1988-02-05','Sp','1','special',N'A Question Of Sport Meets Spitting Image'),
('1988-04-17','Sp','2','special',N'The Ronnie And Nancy Show'),
('1988-05-29','Sp','3','repeat',N'ITV Telethon ''88 (short)'),
('1988-10-29','Sp','4','special',N'Bumbledown'),
('1988-11-06','7','1','new',NULL),('1988-11-13','7','2','new',NULL),
('1988-11-20','7','3','new',NULL),('1988-11-27','7','4','new',NULL),
('1988-12-04','7','5','new',NULL),('1988-12-11','7','6','new',NULL),
-- 1989: special, series 8 and 9
('1989-05-06','Sp','1','special',N'The Sound Of Maggie!'),
('1989-06-11','8','1','new',NULL),('1989-06-18','8','2','new',NULL),
('1989-06-25','8','3','new',NULL),('1989-07-02','8','4','new',NULL),
('1989-07-09','8','5','new',NULL),
('1989-11-12','9','1','new',NULL),('1989-11-19','9','2','new',NULL),
('1989-11-26','9','3','new',NULL),('1989-12-03','9','4','new',NULL),
('1989-12-10','9','5','new',NULL),('1989-12-17','9','6','new',NULL),
-- 1990: series 10 and 11
('1990-05-13','10','1','new',NULL),('1990-05-20','10','2','new',NULL),
('1990-05-27','10','Tel','repeat',N'ITV Telethon ''90 (short)'),
('1990-06-03','10','3','new',NULL),('1990-06-10','10','4','new',NULL),
('1990-06-17','10','5','new',NULL),('1990-06-24','10','6','new',NULL),
('1990-11-11','11','1','new',NULL),('1990-11-18','11','2','new',NULL),
('1990-11-25','11','3','new',NULL),('1990-12-02','11','4','new',NULL),
('1990-12-09','11','5','new',NULL),('1990-12-16','11','6','new',NULL),
-- 1991: series 12 and 13
('1991-04-14','12','1','new',NULL),('1991-04-21','12','2','new',NULL),
('1991-04-28','12','3','new',NULL),('1991-05-05','12','4','new',NULL),
('1991-05-12','12','5','new',NULL),('1991-05-19','12','6','new',NULL),
('1991-11-10','13','1','new',NULL),('1991-11-17','13','2','new',NULL),
('1991-11-24','13','3','new',NULL),('1991-12-01','13','4','new',NULL),
('1991-12-08','13','5','new',NULL),('1991-12-15','13','6','new',NULL),
-- 1992: election special, series 14 and 15
('1992-04-08','Sp','1','special',N'1992 Election Special'),
('1992-04-12','14','1','new',NULL),('1992-04-19','14','2','new',NULL),
('1992-04-26','14','3','new',NULL),('1992-05-03','14','4','new',NULL),
('1992-05-10','14','5','new',NULL),('1992-05-17','14','6','new',NULL),
('1992-07-18','14','Tel','repeat',N'ITV Telethon ''92 (short)'),
('1992-07-25','14','H','repeat',N'Spitting Back 1992'),
('1992-10-04','15','1','new',NULL),('1992-10-11','15','2','new',NULL),
('1992-10-18','15','3','new',NULL),('1992-10-25','15','4','new',NULL),
('1992-11-01','15','5','new',NULL),('1992-11-08','15','6','new',NULL),
-- 1993: series 16 (with Spitting Back repeats) and 17
('1993-05-16','16','1','new',NULL),('1993-05-23','16','2','new',NULL),
('1993-05-30','16','3','new',NULL),('1993-06-06','16','4','new',NULL),
('1993-06-13','16','5','new',NULL),('1993-06-20','16','6','new',NULL),
('1993-06-01','16','H1','repeat',N'Spitting Back 1'),
('1993-06-15','16','H2','repeat',N'Spitting Back 2'),
('1993-07-09','16','H3','repeat',N'Spitting Back 3'),
('1993-07-16','16','H4','repeat',N'Spitting Back 4'),
('1993-07-23','16','H5','repeat',N'Spitting Back 5'),
('1993-07-30','16','H6','repeat',N'Spitting Back 6'),
('1993-11-07','17','1','new',NULL),('1993-11-14','17','2','new',NULL),
('1993-11-21','17','3','new',NULL),('1993-11-28','17','4','new',NULL),
('1993-12-05','17','5','new',NULL),('1993-12-12','17','6','new',NULL),
('1993-12-26','17','Xmas','special',N'The Spitting Image Pantomime'),
-- 1994-95: series 18 and 19
('1994-05-01','18','1','new',NULL),('1994-05-08','18','2','new',NULL),
('1994-05-15','18','3','new',NULL),('1994-05-22','18','4','new',NULL),
('1994-05-29','18','5','new',NULL),('1994-06-05','18','6','new',NULL),
('1994-06-12','18','7','new',NULL),
('1994-11-06','19','1','new',NULL),('1994-11-13','19','2','new',NULL),
('1994-11-20','19','3','new',NULL),('1994-11-27','19','4','new',NULL),
('1994-12-04','19','5','new',NULL),('1994-12-11','19','6','new',NULL),
('1994-12-18','19','7','new',NULL),
('1995-01-01','19','NY','special',N'Ye Olde Spittinge Image New Year Special'),
-- 1996: series 20, the last
('1996-01-14','20','1','new',NULL),('1996-01-21','20','2','new',NULL),
('1996-01-28','20','3','new',NULL),('1996-02-04','20','4','new',NULL),
('1996-02-11','20','5','new',NULL),('1996-02-18','20','6','new',NULL);
GO

-- 152 dated broadcasts (the 1994 compilation has no date). Check:
SELECT Kind, Broadcasts = COUNT(*), First = MIN(AirDate), Last = MAX(AirDate)
FROM hl.SpittingImage GROUP BY Kind;
GO

/* ---------------------------------------------------------------------
   1. One row per Commons sitting day, 1984-1996, with its noise
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #day, #flag;

-- What the Chair's flags are called (whatever 01 defined): look first
SELECT f.Category, Flags = COUNT(*)
FROM hc.ChairFlag AS f
JOIN hc.Speech AS s ON s.SpeechId = f.SpeechId
WHERE s.SittingDate BETWEEN '1984-01-01' AND '1996-12-31'
GROUP BY f.Category ORDER BY Flags DESC;

-- How Odell labels collective shouts (the Shouts measure relies on this)
SELECT TOP (10) ss.DisplayAs, N = COUNT(*)
FROM hc.SourceSpeech AS ss
WHERE ss.DisplayAs LIKE N'%Member%' AND ss.SittingDate < '1997-01-01'
GROUP BY ss.DisplayAs ORDER BY N DESC;

SELECT s.SittingDate,
       Speeches = COUNT(*),
       Shouts   = SUM(CASE WHEN ss.DisplayAs LIKE N'%Hon. Member%'
                           THEN 1 ELSE 0 END)
INTO #day
FROM hc.Speech AS s
JOIN hc.SourceSpeech AS ss ON ss.Id = s.SpeechId
WHERE s.SittingDate BETWEEN '1984-01-01' AND '1996-12-31'
GROUP BY s.SittingDate;

SELECT s.SittingDate, f.Category, Flags = COUNT(*)
INTO #flag
FROM hc.ChairFlag AS f
JOIN hc.Speech AS s ON s.SpeechId = f.SpeechId
WHERE s.SittingDate BETWEEN '1984-01-01' AND '1996-12-31'
GROUP BY s.SittingDate, f.Category;

ALTER TABLE #day ADD Chair int NULL;
UPDATE d SET Chair = ISNULL((SELECT SUM(Flags) FROM #flag AS f
                             WHERE f.SittingDate = d.SittingDate), 0)
FROM #day AS d;

/* ---------------------------------------------------------------------
   2. Which sitting days follow a broadcast?
      "After" = the first sitting day within 3 days of a new episode
      or special (Sunday night -> Monday; a Friday special -> Monday).
      Placebo = the same, with every date moved 26 weeks.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #tag;

SELECT d.*,
       Dow = DATENAME(weekday, d.SittingDate),
       Yr  = YEAR(d.SittingDate),
       After = CASE WHEN EXISTS (
                   SELECT 1 FROM hl.SpittingImage AS b
                   WHERE b.Kind IN ('new', 'special')
                     AND d.SittingDate > b.AirDate
                     AND d.SittingDate <= DATEADD(day, 3, b.AirDate)
                     AND NOT EXISTS (SELECT 1 FROM #day AS e   -- first one only
                                     WHERE e.SittingDate > b.AirDate
                                       AND e.SittingDate < d.SittingDate))
                   THEN 1 ELSE 0 END,
       Placebo = CASE WHEN EXISTS (
                   SELECT 1 FROM hl.SpittingImage AS b
                   CROSS APPLY (SELECT Fake = DATEADD(week, 26, b.AirDate)) AS p
                   WHERE b.Kind IN ('new', 'special')
                     AND d.SittingDate > p.Fake
                     AND d.SittingDate <= DATEADD(day, 3, p.Fake)
                     AND NOT EXISTS (SELECT 1 FROM hl.SpittingImage AS r
                                     WHERE r.AirDate BETWEEN DATEADD(day, -6, p.Fake)
                                                         AND p.Fake)
                     AND NOT EXISTS (SELECT 1 FROM #day AS e
                                     WHERE e.SittingDate > p.Fake
                                       AND e.SittingDate < d.SittingDate))
                   THEN 1 ELSE 0 END
INTO #tag
FROM #day AS d;

-- How many days fall in each group (the placebo excludes real show weeks)
SELECT Dow, AfterShow = SUM(After), Placebo = SUM(Placebo), AllDays = COUNT(*)
FROM #tag GROUP BY Dow ORDER BY AllDays DESC;
GO

/* ---------------------------------------------------------------------
   3. A and B: the day after vs every other day of the same weekday.
      Rates per 1,000 speeches, averaged over days, with a Welch t:
      above about 2 (or below -2) is worth a second look.
   --------------------------------------------------------------------- */
WITH r AS (
    SELECT t.*,
           ChairK = 1000.0 * t.Chair  / NULLIF(t.Speeches, 0),
           ShoutK = 1000.0 * t.Shouts / NULLIF(t.Speeches, 0)
    FROM #tag AS t
    WHERE t.Speeches >= 50                    -- skip near-empty days
),
g AS (
    SELECT Test = 'A: day after the show', Dow, Grp = After, ChairK, ShoutK
    FROM r WHERE Placebo = 0
    UNION ALL
    SELECT 'B: placebo, 26 weeks on', Dow, Placebo, ChairK, ShoutK
    FROM r WHERE After = 0
),
s AS (
    SELECT Test, Dow, Grp, N = COUNT(*),
           ChairMean = AVG(ChairK), ChairVar = VAR(ChairK),
           ShoutMean = AVG(ShoutK), ShoutVar = VAR(ShoutK)
    FROM g GROUP BY Test, Dow, Grp
)
SELECT y.Test, y.Dow,
       DaysAfter = y.N, DaysOther = n.N,
       ChairAfter = CAST(y.ChairMean AS decimal(7,1)),
       ChairOther = CAST(n.ChairMean AS decimal(7,1)),
       ChairT = CAST((y.ChairMean - n.ChairMean)
                / NULLIF(SQRT(y.ChairVar / y.N + n.ChairVar / n.N), 0)
                AS decimal(5,2)),
       ShoutAfter = CAST(y.ShoutMean AS decimal(7,1)),
       ShoutOther = CAST(n.ShoutMean AS decimal(7,1)),
       ShoutT = CAST((y.ShoutMean - n.ShoutMean)
                / NULLIF(SQRT(y.ShoutVar / y.N + n.ShoutVar / n.N), 0)
                AS decimal(5,2))
FROM s AS y
JOIN s AS n ON n.Test = y.Test AND n.Dow = y.Dow AND n.Grp = 0
WHERE y.Grp = 1 AND y.N >= 10
ORDER BY y.Test, y.N DESC;
GO

-- The same, one row per Chair category, Mondays only
WITH m AS (
    SELECT t.SittingDate, t.Speeches, t.After, t.Placebo
    FROM #tag AS t
    WHERE t.Dow = 'Monday' AND t.Speeches >= 50
),
c AS (SELECT DISTINCT Category FROM #flag),
x AS (
    SELECT c.Category, m.After, m.Placebo,
           K = 1000.0 * ISNULL(f.Flags, 0) / m.Speeches
    FROM m CROSS JOIN c
    LEFT JOIN #flag AS f ON f.SittingDate = m.SittingDate
                        AND f.Category = c.Category
)
SELECT Category,
       AfterShow = CAST(AVG(CASE WHEN After = 1 THEN K END) AS decimal(7,2)),
       Placebo   = CAST(AVG(CASE WHEN Placebo = 1 THEN K END) AS decimal(7,2)),
       Neither   = CAST(AVG(CASE WHEN After = 0 AND Placebo = 0 THEN K END)
                        AS decimal(7,2))
FROM x
GROUP BY Category
ORDER BY Category;
GO

/* ---------------------------------------------------------------------
   4. C: the puppets. Shouts aimed at well-known targets (filed under
      whoever had the floor, as in Order! Order!) in the three sitting
      days after a broadcast, against all their other days.
      Per-episode cast lists aren't published, so this uses the
      regulars. Edit the list to taste; names are Odell's DisplayAs.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #puppet, #win, #aim, #pp;

CREATE TABLE #puppet (Name nvarchar(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8);
INSERT #puppet VALUES
 (N'Margaret Thatcher'), (N'Neil Kinnock'), (N'David Steel'), (N'David Owen'),
 (N'Norman Tebbit'), (N'Michael Heseltine'), (N'Geoffrey Howe'),
 (N'Nigel Lawson'), (N'Roy Hattersley'), (N'John Major'), (N'Douglas Hurd'),
 (N'Jeremy Ashdown'), (N'Kenneth Baker'), (N'Denis Healey'),
 (N'Michael Foot'), (N'Leon Brittan'), (N'Cecil Parkinson'),
 (N'Kenneth Clarke'), (N'Norman Lamont'), (N'Edwina Currie'),
 (N'David Mellor'), (N'Peter Bottomley'), (N'Tony Benn'), (N'Antony Benn'),
 (N'Dennis Skinner'), (N'John Prescott'), (N'Tony Blair'),
 (N'Gordon Brown'), (N'Michael Portillo'), (N'Nicholas Ridley');

-- sitting days in the 3-day window after a new episode or special
SELECT DISTINCT d.SittingDate
INTO #win
FROM #day AS d
JOIN hl.SpittingImage AS b
  ON b.Kind IN ('new', 'special')
 AND d.SittingDate > b.AirDate
 AND d.SittingDate <= DATEADD(day, 4, b.AirDate);   -- Mon to Thu

SELECT x.SittingDate, x.DisplayAs, x.IsShout, Target = x.Target
INTO #aim
FROM (SELECT s.SittingDate, ss.DisplayAs,
             IsShout = CASE WHEN ss.DisplayAs LIKE N'%Hon. Member%'
                            THEN 1 ELSE 0 END,
             Target = LAG(CASE WHEN s.Role = 'Member'
                                AND ss.DisplayAs NOT LIKE N'%Hon. Member%'
                               THEN ss.DisplayAs END) IGNORE NULLS
                      OVER (PARTITION BY s.SittingDate
                            ORDER BY s.Seq, s.SpeechId)
      FROM hc.Speech AS s
      JOIN hc.SourceSpeech AS ss ON ss.Id = s.SpeechId
      WHERE s.SittingDate BETWEEN '1984-01-01' AND '1996-12-31') AS x;

SELECT p.Name,
       SpeechesAfter = SUM(CASE WHEN w.SittingDate IS NOT NULL
                                 AND a.DisplayAs = p.Name THEN 1 ELSE 0 END),
       SpeechesOther = SUM(CASE WHEN w.SittingDate IS NULL
                                 AND a.DisplayAs = p.Name THEN 1 ELSE 0 END),
       ShoutsAfter   = SUM(CASE WHEN w.SittingDate IS NOT NULL
                                 AND a.IsShout = 1 AND a.Target = p.Name
                                THEN 1 ELSE 0 END),
       ShoutsOther   = SUM(CASE WHEN w.SittingDate IS NULL
                                 AND a.IsShout = 1 AND a.Target = p.Name
                                THEN 1 ELSE 0 END)
INTO #pp
FROM #puppet AS p
JOIN #aim AS a ON a.DisplayAs = p.Name OR a.Target = p.Name
LEFT JOIN #win AS w ON w.SittingDate = a.SittingDate
GROUP BY p.Name;

SELECT Name, SpeechesAfter, SpeechesOther,
       PerKAfter = CAST(1000.0 * ShoutsAfter / NULLIF(SpeechesAfter, 0)
                        AS decimal(7,1)),
       PerKOther = CAST(1000.0 * ShoutsOther / NULLIF(SpeechesOther, 0)
                        AS decimal(7,1))
FROM #pp
WHERE SpeechesAfter >= 20
ORDER BY 1.0 * ShoutsAfter / NULLIF(SpeechesAfter, 0)
       - 1.0 * ShoutsOther / NULLIF(SpeechesOther, 0) DESC;

-- All the puppets together, against every other MP
SELECT Who = CASE WHEN p.Name IS NULL THEN 'everyone else' ELSE 'puppets' END,
       ShoutsPerKAfter = CAST(1000.0 * SUM(CASE WHEN w.SittingDate IS NOT NULL
                              AND a.IsShout = 1 THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CASE WHEN w.SittingDate IS NOT NULL
                              AND a.IsShout = 0 THEN 1 ELSE 0 END), 0)
                       AS decimal(7,1)),
       ShoutsPerKOther = CAST(1000.0 * SUM(CASE WHEN w.SittingDate IS NULL
                              AND a.IsShout = 1 THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CASE WHEN w.SittingDate IS NULL
                              AND a.IsShout = 0 THEN 1 ELSE 0 END), 0)
                       AS decimal(7,1))
FROM #aim AS a
LEFT JOIN #puppet AS p
  ON p.Name = CASE WHEN a.IsShout = 1 THEN a.Target ELSE a.DisplayAs END
LEFT JOIN #win AS w ON w.SittingDate = a.SittingDate
WHERE a.Target IS NOT NULL OR a.IsShout = 0
GROUP BY CASE WHEN p.Name IS NULL THEN 'everyone else' ELSE 'puppets' END;
GO

/* ---------------------------------------------------------------------
   5. Placebo for C. The puppets were heckled a little more after a
      show while everyone else was heckled less, so check it the same
      way as A: move every broadcast 26 weeks and see whether the
      gap survives. Mondays to Thursdays only, on both sides, so the
      window and the rest have the same mix of days (PMQs included).
      Needs #day, #puppet and #aim from sections 1 and 4.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #win2;

SELECT DISTINCT d.SittingDate, Kind = CAST('real' AS varchar(10))
INTO #win2
FROM #day AS d
JOIN hl.SpittingImage AS b
  ON b.Kind IN ('new', 'special')
 AND d.SittingDate > b.AirDate
 AND d.SittingDate <= DATEADD(day, 4, b.AirDate);

INSERT #win2 (SittingDate, Kind)
SELECT DISTINCT d.SittingDate, 'placebo'
FROM #day AS d
JOIN hl.SpittingImage AS b ON b.Kind IN ('new', 'special')
CROSS APPLY (SELECT Fake = DATEADD(week, 26, b.AirDate)) AS p
WHERE d.SittingDate > p.Fake
  AND d.SittingDate <= DATEADD(day, 4, p.Fake)
  AND NOT EXISTS (SELECT 1 FROM #win2 AS w
                  WHERE w.Kind = 'real' AND w.SittingDate = d.SittingDate);

WITH a AS (
    SELECT a.*,
           Who = CASE WHEN p.Name IS NULL THEN 'everyone else'
                      ELSE 'puppets' END
    FROM #aim AS a
    LEFT JOIN #puppet AS p
      ON p.Name = CASE WHEN a.IsShout = 1 THEN a.Target
                       ELSE a.DisplayAs END
    WHERE DATENAME(weekday, a.SittingDate)
          IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday')
      AND (a.IsShout = 0 OR a.Target IS NOT NULL)
),
t AS (
    SELECT k.Kind, a.Who,
           InWin = CASE WHEN w.SittingDate IS NULL THEN 0 ELSE 1 END,
           a.IsShout
    FROM a
    CROSS JOIN (VALUES ('real'), ('placebo')) AS k(Kind)
    LEFT JOIN #win2 AS w ON w.SittingDate = a.SittingDate
                        AND w.Kind = k.Kind
    -- the placebo's "rest" leaves out the real windows, and vice versa
    WHERE NOT EXISTS (SELECT 1 FROM #win2 AS o
                      WHERE o.SittingDate = a.SittingDate
                        AND o.Kind <> k.Kind)
)
SELECT Kind, Who,
       PerKInWindow = CAST(1000.0 * SUM(CASE WHEN InWin = 1 THEN IsShout END)
                      / NULLIF(SUM(CASE WHEN InWin = 1 THEN 1 - IsShout END), 0)
                      AS decimal(7,1)),
       PerKRest     = CAST(1000.0 * SUM(CASE WHEN InWin = 0 THEN IsShout END)
                      / NULLIF(SUM(CASE WHEN InWin = 0 THEN 1 - IsShout END), 0)
                      AS decimal(7,1)),
       Shouts = SUM(IsShout)
FROM t
GROUP BY Kind, Who
ORDER BY Kind DESC, Who DESC;
GO

/* ---------------------------------------------------------------------
   6. Two harder checks on the puppet result.
      a) A same-season placebo. Moving 26 weeks also changes the season,
         and the real shows cluster in Nov-Dec and Apr-Jun, when the
         Queen's Speech and the Budget fill the House. So move each
         date 1 to 3 weeks either side instead, keeping only days that
         aren't in a real window: the weeks just before and after
         each series, in the same season.
      b) Leave out the three biggest gainers (Kinnock, Heseltine,
         Blair). If the effect is just them, it isn't the show.
      Needs #day, #puppet, #aim and #win2 from sections 1, 4 and 5.
   --------------------------------------------------------------------- */
DELETE #win2 WHERE Kind = 'near';

INSERT #win2 (SittingDate, Kind)
SELECT DISTINCT d.SittingDate, 'near'
FROM #day AS d
JOIN hl.SpittingImage AS b ON b.Kind IN ('new', 'special')
CROSS JOIN (VALUES (-21), (-14), (-7), (7), (14), (21)) AS sh(Days)
CROSS APPLY (SELECT Fake = DATEADD(day, sh.Days, b.AirDate)) AS p
WHERE d.SittingDate > p.Fake
  AND d.SittingDate <= DATEADD(day, 4, p.Fake)
  AND NOT EXISTS (SELECT 1 FROM #win2 AS w
                  WHERE w.Kind = 'real' AND w.SittingDate = d.SittingDate);

-- how many days each window holds
SELECT Kind, Days = COUNT(*) FROM #win2 GROUP BY Kind;

WITH a AS (
    SELECT a.*,
           Who = CASE WHEN p.Name IS NULL THEN 'everyone else'
                      WHEN p.Name IN (N'Neil Kinnock', N'Michael Heseltine',
                                      N'Tony Blair')
                      THEN 'puppets: top 3'
                      ELSE 'puppets: the rest' END
    FROM #aim AS a
    LEFT JOIN #puppet AS p
      ON p.Name = CASE WHEN a.IsShout = 1 THEN a.Target
                       ELSE a.DisplayAs END
    WHERE DATENAME(weekday, a.SittingDate)
          IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday')
      AND (a.IsShout = 0 OR a.Target IS NOT NULL)
),
t AS (
    SELECT k.Kind, a.Who,
           InWin = CASE WHEN w.SittingDate IS NULL THEN 0 ELSE 1 END,
           a.IsShout
    FROM a
    CROSS JOIN (VALUES ('real'), ('near')) AS k(Kind)
    LEFT JOIN #win2 AS w ON w.SittingDate = a.SittingDate
                        AND w.Kind = k.Kind
    WHERE NOT EXISTS (SELECT 1 FROM #win2 AS o
                      WHERE o.SittingDate = a.SittingDate
                        AND o.Kind <> k.Kind
                        AND o.Kind IN ('real', 'near'))
)
SELECT Kind, Who,
       PerKInWindow = CAST(1000.0 * SUM(CASE WHEN InWin = 1 THEN IsShout END)
                      / NULLIF(SUM(CASE WHEN InWin = 1 THEN 1 - IsShout END), 0)
                      AS decimal(7,1)),
       PerKRest     = CAST(1000.0 * SUM(CASE WHEN InWin = 0 THEN IsShout END)
                      / NULLIF(SUM(CASE WHEN InWin = 0 THEN 1 - IsShout END), 0)
                      AS decimal(7,1)),
       ShoutsInWindow = SUM(CASE WHEN InWin = 1 THEN IsShout END),
       SpeechesInWindow = SUM(CASE WHEN InWin = 1 THEN 1 - IsShout END)
FROM t
GROUP BY Kind, Who
ORDER BY Kind DESC, Who DESC;
GO
