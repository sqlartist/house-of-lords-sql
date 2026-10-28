/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   05_new_angles.sql : the things nobody has pieced together before,
   because they need both Houses joined on the same person.

   A  Stephen Benn: his record, his father, and the vote that removed him
   B  "How can we get rid of you?": Benn's fifth question in the Lords
   C  Sitcoms in Hansard: Spitting Image, Alan B'Stard, Yes Minister...
   D  Rebuked in the Commons, rewarded with a peerage?
   E  Are ex-MPs looked down on? Who the Lords shouts at
   F  Does ermine change the voice? Same people, both Houses

   Needs 01 and 02 run. D also needs the Commons hypercube build
   (hc.Speech and hc.ChairFlag from Order! Order!). C scans every
   speech in both Houses for text, so it takes a few minutes.
   ===================================================================== */
USE [HANSARD];
GO

DECLARE @stansgate nvarchar(100) =
    (SELECT TOP (1) PersonId FROM hl.Person WHERE DisplayName = N'Viscount Stansgate');

/* ---------------------------------------------------------------------
   A  Stephen Benn
   --------------------------------------------------------------------- */
-- His seats: elected hereditary from 2021, removed April 2026, back in June
SELECT House, Party, PeerageType, StartDate, EndDate, EndReason
FROM hl.Membership WHERE PersonId = @stansgate ORDER BY StartDate;

-- How much he says, year by year
SELECT Yr = YEAR(SittingDate), Speeches = COUNT(*),
       Words = SUM(LEN(Body) - LEN(REPLACE(Body, N' ', N'')) + 1)
FROM hl.SourceSpeech
WHERE PersonId = @stansgate AND SpeechClass = 'Speech'
GROUP BY YEAR(SittingDate) ORDER BY Yr;

-- What he talks about: the debates he speaks in most
SELECT TOP (25) Debate = ISNULL(MajorHeading, MinorHeading), Speeches = COUNT(*), FirstTime = MIN(SittingDate)
FROM hl.SourceSpeech
WHERE PersonId = @stansgate AND SpeechClass = 'Speech'
GROUP BY ISNULL(MajorHeading, MinorHeading) ORDER BY Speeches DESC;

-- Does he invoke his father, or the questions?
SELECT SittingDate, MajorHeading, Excerpt = SUBSTRING(Body, PATINDEX(N'%[Ff]ather%', Body + N'father') - 150, 400)
FROM hl.SourceSpeech
WHERE PersonId = @stansgate
  AND (Body LIKE N'%my father%' OR Body LIKE N'%Tony Benn%' OR Body LIKE N'%get rid of you%'
       OR Body LIKE N'%disclaim%' OR Body LIKE N'%Peerage Act%')
ORDER BY SittingDate;

-- Loyalty: his votes against the Labour majority in each division
WITH v AS (
    SELECT v.DivisionGid, v.PersonId, v.Vote, seat.Party
    FROM hl.Vote AS v
    JOIN hl.Division AS d ON d.DivisionGid = v.DivisionGid
    OUTER APPLY hl.fnSeatOn(v.PersonId, d.SittingDate) AS seat
    WHERE v.PersonId IS NOT NULL AND d.SittingDate >= '2021-07-01'
),
line AS (
    SELECT DivisionGid, Line = CASE WHEN SUM(CASE WHEN Vote = 'content' THEN 1 ELSE -1 END) > 0 THEN 'content' ELSE 'not-content' END
    FROM v WHERE Party = N'labour' GROUP BY DivisionGid
    HAVING SUM(CASE WHEN Vote = 'content' THEN 1 ELSE -1 END) <> 0
)
SELECT Who = CASE WHEN v.PersonId = @stansgate THEN 'Stephen Benn' ELSE 'other Labour peers' END,
       Votes = COUNT(*),
       RebelPct = CAST(100.0 * SUM(CASE WHEN v.Vote <> l.Line THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2)),
       VotesPerPeer = COUNT(*) / COUNT(DISTINCT v.PersonId)
FROM v JOIN line AS l ON l.DivisionGid = v.DivisionGid
WHERE v.Party = N'labour'
GROUP BY CASE WHEN v.PersonId = @stansgate THEN 'Stephen Benn' ELSE 'other Labour peers' END;

-- The vote on his own removal: every division on the hereditary peers bill, and how he voted
SELECT d.SittingDate, d.MajorHeading, d.MinorHeading, d.Contents, d.NotContents,
       StephenBenn = (SELECT TOP (1) Vote FROM hl.Vote AS v WHERE v.DivisionGid = d.DivisionGid AND v.PersonId = @stansgate)
FROM hl.Division AS d
WHERE d.MajorHeading LIKE N'%Hereditary Peers%' OR d.MinorHeading LIKE N'%Hereditary Peers%'
ORDER BY d.SittingDate, d.DivNumber;

-- And what he said in those debates
SELECT SittingDate, MajorHeading, Body
FROM hl.SourceSpeech
WHERE PersonId = @stansgate AND (MajorHeading LIKE N'%Hereditary Peers%' OR MinorHeading LIKE N'%Hereditary Peers%')
ORDER BY SittingDate, Seq;
GO

/* ---------------------------------------------------------------------
   B  Benn's fifth question, "how can we get rid of you?", in the
   chamber it fits best: the one nobody can be voted out of.
   --------------------------------------------------------------------- */
SELECT s.SittingDate, s.SpeakerName, Party = seat.Party, s.MajorHeading,
       Excerpt = SUBSTRING(s.Body, PATINDEX(N'%get rid of %', s.Body) - 250, 450)
FROM hl.SourceSpeech AS s
OUTER APPLY hl.fnSeatOn(s.PersonId, s.SittingDate) AS seat
WHERE s.Body LIKE N'%get rid of you%' AND s.Body LIKE N'%power%'
ORDER BY s.SittingDate;

SELECT s.SittingDate, s.SpeakerName, s.MajorHeading,
       Excerpt = SUBSTRING(s.Body, PATINDEX(N'%Benn%', s.Body) - 200, 400)
FROM hl.SourceSpeech AS s
WHERE s.Body LIKE N'%Tony Benn%' OR s.Body LIKE N'%Mr Benn%' OR s.Body LIKE N'%Wedgwood Benn%'
ORDER BY s.SittingDate;
GO

/* ---------------------------------------------------------------------
   C  Sitcoms in Hansard. Both Houses, by year. This is the slow one
   (every speech against every pattern): run it on its own if you like. 'New Statesman' is also
   a magazine, so B'Stard is searched by name only.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #show;
CREATE TABLE #show (Show nvarchar(40), Pattern nvarchar(60));
INSERT #show VALUES
    (N'Spitting Image', N'%Spitting Image%'),
    (N'Alan B''Stard',  N'%B''Stard%'), (N'Alan B''Stard', N'%Bstard%'), (N'Alan B''Stard', N'%B''stard%'),
    (N'Yes Minister',   N'%Yes Minister%'), (N'Yes Minister', N'%Yes, Minister%'), (N'Yes Minister', N'%Sir Humphrey%'),
    (N'Yes Minister',   N'%Yes, Prime Minister%'), (N'Yes Minister', N'%Jim Hacker%'),
    (N'The Thick of It', N'%Thick of It%'), (N'The Thick of It', N'%Malcolm Tucker%'),
    (N'Blackadder',     N'%Blackadder%'), (N'Monty Python', N'%Monty Python%'), (N'Monty Python', N'%dead parrot%'),
    (N'Fawlty Towers',  N'%Fawlty%'), (N'Dad''s Army', N'%Dad''s Army%'), (N'Dad''s Army', N'%Captain Mainwaring%'),
    (N'Only Fools',     N'%Del Boy%'), (N'House of Cards', N'%Francis Urquhart%'),
    (N'House of Cards', N'%you might very well think that%');

DROP TABLE IF EXISTS #hits;
SELECT House = 'Commons', K = 'C' + CAST(s.Id AS varchar(20)), s.SittingDate,
       Speaker = s.DisplayAs COLLATE Latin1_General_100_CI_AS_SC_UTF8, Show = sh.Show COLLATE Latin1_General_100_CI_AS_SC_UTF8, Pattern = sh.Pattern COLLATE Latin1_General_100_CI_AS_SC_UTF8, Body = s.Body COLLATE Latin1_General_100_CI_AS_SC_UTF8
INTO #hits
FROM hc.SourceSpeech AS s JOIN #show AS sh
  ON s.Body COLLATE Latin1_General_100_CI_AS_SC_UTF8 LIKE sh.Pattern COLLATE Latin1_General_100_CI_AS_SC_UTF8   -- the tables and tempdb use different collations
UNION ALL
SELECT 'Lords', 'L' + CAST(s.Id AS varchar(20)), s.SittingDate,
       s.SpeakerName COLLATE Latin1_General_100_CI_AS_SC_UTF8, sh.Show COLLATE Latin1_General_100_CI_AS_SC_UTF8, sh.Pattern COLLATE Latin1_General_100_CI_AS_SC_UTF8, s.Body COLLATE Latin1_General_100_CI_AS_SC_UTF8
FROM hl.SourceSpeech AS s JOIN #show AS sh
  ON s.Body COLLATE Latin1_General_100_CI_AS_SC_UTF8 LIKE sh.Pattern COLLATE Latin1_General_100_CI_AS_SC_UTF8;

-- 'in the thick of it' is an ordinary phrase: only count it once the show existed (first broadcast 19 May 2005)
DELETE #hits WHERE Show = N'The Thick of It' AND Pattern = N'%Thick of It%' AND SittingDate < '2005-05-19';

-- Mentions per show per House, and when each peaked
SELECT Show, House, Mentions = COUNT(DISTINCT K), FirstSeen = MIN(SittingDate), LastSeen = MAX(SittingDate)
FROM #hits GROUP BY Show, House ORDER BY Mentions DESC;

SELECT Yr = YEAR(SittingDate), Show, Mentions = COUNT(DISTINCT K)
FROM #hits GROUP BY YEAR(SittingDate), Show ORDER BY Show, Yr;

-- Who uses them most, and the lines themselves
SELECT TOP (25) House, Speaker, Mentions = COUNT(DISTINCT K), Shows = STRING_AGG(Show, N', ')
FROM (SELECT DISTINCT House, K, Speaker, Show FROM #hits) AS h
GROUP BY House, Speaker ORDER BY Mentions DESC;

SELECT House, SittingDate, Speaker, Show,                -- one row per speech, even when several patterns match it
       Excerpt = SUBSTRING(Body, PATINDEX(Pattern, Body) - 200, 450)
FROM (SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY K, Show ORDER BY Pattern) FROM #hits) AS h
WHERE rn = 1
ORDER BY Show, SittingDate;
GO

/* ---------------------------------------------------------------------
   D  Rebuked, then rewarded? For every MP who spoke 1979-2021 and has
   left the Commons, how often the Chair rebuked them personally (sit
   down, withdraw, named), and whether they ended up in the Lords.
   Prominence drives both rebukes and peerages, so compare within bands
   of speeches made.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #x, #reb, #mp;

SELECT s.SpeechId, s.SittingDate, s.Seq, s.Role, cn.PersonId
INTO #x
FROM hc.Speech AS s
JOIN hc.SourceSpeech AS ss ON ss.Id = s.SpeechId
LEFT JOIN hl.CommonsName AS cn ON cn.DisplayAs = ss.DisplayAs AND cn.Yr = YEAR(s.SittingDate);

SELECT t.PersonId,
       Rebukes = COUNT(DISTINCT CASE WHEN f.Category IN ('SEAT', 'WITHDRAW', 'NAME') THEN t.SpeechId END),
       Named   = COUNT(DISTINCT CASE WHEN f.Category = 'NAME' THEN t.SpeechId END)
INTO #reb
FROM (SELECT x.SpeechId, x.Role,
             PersonId = LAG(CASE WHEN x.Role = 'Member' THEN x.PersonId END) IGNORE NULLS
                        OVER (PARTITION BY x.SittingDate ORDER BY x.Seq, x.SpeechId)
      FROM #x AS x) AS t
JOIN hc.ChairFlag AS f ON f.SpeechId = t.SpeechId
WHERE t.Role IN ('Speaker', 'Deputy', 'Committee') AND t.PersonId IS NOT NULL
GROUP BY t.PersonId;

SELECT k.PersonId, p.DisplayName,
       Speeches = (SELECT SUM(Speeches) FROM hl.CommonsName AS c WHERE c.PersonId = k.PersonId),
       Rebukes  = ISNULL(r.Rebukes, 0), Named = ISNULL(r.Named, 0),
       k.WhipLost, k.Resigned, k.LeftCommons,
       Peer = CASE WHEN EXISTS (SELECT 1 FROM hl.Membership AS l
                                WHERE l.PersonId = k.PersonId AND l.House = 'Lords'
                                  AND (l.StartDate IS NULL OR l.StartDate >= k.LeftCommons)) THEN 1 ELSE 0 END
INTO #mp
FROM (SELECT PersonId,
             LeftCommons = MAX(ISNULL(EndDate, '9999-12-31')),
             WhipLost = MAX(CASE WHEN EndReason = 'whip_removed' THEN 1 ELSE 0 END),
             Resigned = MAX(CASE WHEN EndReason IN ('resigned', 'recall_petition', 'disqualified') THEN 1 ELSE 0 END)
      FROM hl.Membership WHERE House = 'Commons' GROUP BY PersonId) AS k
JOIN hl.Person AS p ON p.PersonId = k.PersonId
LEFT JOIN #reb AS r ON r.PersonId = k.PersonId
WHERE k.LeftCommons < '2024-07-04'                                    -- has actually left
  AND k.PersonId IN (SELECT PersonId FROM hl.CommonsName);            -- and spoke 1979-2021

-- Peerage rate by rebukes, within bands of prominence
SELECT Band = CASE WHEN Speeches < 500 THEN '1: <500 speeches' WHEN Speeches < 2000 THEN '2: 500-2,000'
                   ELSE '3: 2,000+' END,
       Rebuked = CASE WHEN Rebukes = 0 THEN '0 rebukes' WHEN Rebukes < 5 THEN '1-4' ELSE '5+' END,
       MPs = COUNT(*), Peers = SUM(Peer),
       PeerPct = CAST(100.0 * SUM(Peer) / COUNT(*) AS decimal(5,1))
FROM #mp
GROUP BY CASE WHEN Speeches < 500 THEN '1: <500 speeches' WHEN Speeches < 2000 THEN '2: 500-2,000' ELSE '3: 2,000+' END,
         CASE WHEN Rebukes = 0 THEN '0 rebukes' WHEN Rebukes < 5 THEN '1-4' ELSE '5+' END
ORDER BY Band, Rebuked;

-- Lost the whip or resigned, against everyone else
SELECT Trouble = CASE WHEN WhipLost = 1 THEN 'lost the whip' WHEN Resigned = 1 THEN 'resigned / recalled'
                      WHEN Named > 0 THEN 'named by the Speaker' ELSE 'none of these' END,
       MPs = COUNT(*), Peers = SUM(Peer), PeerPct = CAST(100.0 * SUM(Peer) / COUNT(*) AS decimal(5,1))
FROM #mp
GROUP BY CASE WHEN WhipLost = 1 THEN 'lost the whip' WHEN Resigned = 1 THEN 'resigned / recalled'
              WHEN Named > 0 THEN 'named by the Speaker' ELSE 'none of these' END;

-- The rebuked who went upstairs, most rebuked first
SELECT TOP (30) DisplayName, Speeches, Rebukes, Named, WhipLost, Resigned, LeftCommons
FROM #mp WHERE Peer = 1 ORDER BY Rebukes DESC;
GO

/* ---------------------------------------------------------------------
   E  Are ex-MPs looked down on? Each collective shout ("Oh!",
   "Order!", "Too long!") filed under the peer who had the floor, as
   the hypercube does for the Commons. Rate per 1,000 speeches.
   --------------------------------------------------------------------- */
WITH t AS (
    SELECT s.SittingDate, s.SpeakerName, s.Body,
           Target = LAG(s.PersonId) IGNORE NULLS OVER (PARTITION BY s.SittingDate ORDER BY s.Seq)
    FROM hl.SourceSpeech AS s
),
shouts AS (
    SELECT Target, Shouts = COUNT(*),
           Order_ = SUM(CASE WHEN Body LIKE N'%Order%' THEN 1 ELSE 0 END),
           TooLong = SUM(CASE WHEN Body LIKE N'%Too long%' OR Body LIKE N'%Time%' OR Body LIKE N'%Next%' THEN 1 ELSE 0 END)
    FROM t
    WHERE SpeakerName IN (N'Noble Lords', N'A noble Lord', N'Several noble Lords', N'A noble Baroness')
      AND YEAR(SittingDate) NOT IN (2016, 2017, 2018)                 -- the recording gap
      AND Target IS NOT NULL
    GROUP BY Target
),
said AS (
    SELECT PersonId, Speeches = COUNT(*) FROM hl.SourceSpeech
    WHERE SpeechClass = 'Speech' AND PersonId IS NOT NULL AND YEAR(SittingDate) NOT IN (2016, 2017, 2018)
    GROUP BY PersonId
)
SELECT Route = CASE WHEN p.ExMP = 1 THEN 'ex-MP' WHEN p.PeerageType IN ('HP', 'HD', 'HO') THEN 'hereditary'
                    WHEN p.PeerageType = 'B' THEN 'bishop' ELSE 'life, never an MP' END,
       Peers = COUNT(*), Speeches = SUM(sd.Speeches), Shouts = SUM(ISNULL(sh.Shouts, 0)),
       ShoutsPerK = CAST(1000.0 * SUM(ISNULL(sh.Shouts, 0)) / SUM(sd.Speeches) AS decimal(6,2)),
       TooLongPerK = CAST(1000.0 * SUM(ISNULL(sh.TooLong, 0)) / SUM(sd.Speeches) AS decimal(6,2))
FROM hl.vPeer AS p
JOIN said AS sd ON sd.PersonId = p.PersonId
LEFT JOIN shouts AS sh ON sh.Target = p.PersonId
GROUP BY CASE WHEN p.ExMP = 1 THEN 'ex-MP' WHEN p.PeerageType IN ('HP', 'HD', 'HO') THEN 'hereditary'
              WHEN p.PeerageType = 'B' THEN 'bishop' ELSE 'life, never an MP' END;
GO

/* ---------------------------------------------------------------------
   F  Does ermine change the voice? For each person who spoke in both
   Houses: average speech length, and share of speeches that ask a
   question, Commons against Lords.
   --------------------------------------------------------------------- */
WITH c AS (
    SELECT cn.PersonId, Speeches = COUNT(*),
           AvgWords = AVG(1.0 * (LEN(s.Body) - LEN(REPLACE(s.Body, N' ', N'')) + 1)),
           QPct = 100.0 * AVG(CASE WHEN s.Body LIKE N'%?%' THEN 1.0 ELSE 0 END)
    FROM hc.SourceSpeech AS s
    JOIN hl.CommonsName AS cn ON cn.DisplayAs = s.DisplayAs AND cn.Yr = YEAR(s.SittingDate)
    GROUP BY cn.PersonId
),
l AS (
    SELECT s.PersonId, Speeches = COUNT(*),
           AvgWords = AVG(1.0 * (LEN(s.Body) - LEN(REPLACE(s.Body, N' ', N'')) + 1)),
           QPct = 100.0 * AVG(CASE WHEN s.Body LIKE N'%?%' THEN 1.0 ELSE 0 END)
    FROM hl.SourceSpeech AS s
    WHERE s.SpeechClass = 'Speech' AND s.PersonId IS NOT NULL
    GROUP BY s.PersonId
)
SELECT p.DisplayName, CommonsSpeeches = c.Speeches, LordsSpeeches = l.Speeches,
       CommonsWords = CAST(c.AvgWords AS int), LordsWords = CAST(l.AvgWords AS int),
       LengthRatio = CAST(l.AvgWords / NULLIF(c.AvgWords, 0) AS decimal(5,2)),
       CommonsQPct = CAST(c.QPct AS decimal(5,1)), LordsQPct = CAST(l.QPct AS decimal(5,1))
FROM c JOIN l ON l.PersonId = c.PersonId
JOIN hl.Person AS p ON p.PersonId = c.PersonId
WHERE c.Speeches >= 200 AND l.Speeches >= 100
ORDER BY LengthRatio DESC;
GO
