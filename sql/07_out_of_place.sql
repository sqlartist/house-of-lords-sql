/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   07_out_of_place.sql : speeches that don't belong in their own debate.

   The "coded message" test. A message hidden in a speech has to be
   said in a debate about something else, so it should sit a long way,
   in meaning, from everything said around it. Your embeddings can
   measure that directly.

   For every debate (same day, same heading and subheading):
     1. find the debate's dominant topic cluster (dbo.speech_sig)
     2. measure each speech's cosine distance from that cluster's
        centroid, and score it against the rest of the debate (z-score)
     3. for the shortlist, check its nearest neighbour in the debate:
        a real outlier is far even from the speech most like it
     4. find the cluster it actually belongs to, and what that cluster
        is usually about

   Most of what comes out will be innocent: a constituency plug, a
   joke, an MP wandering off-topic, a misfiled Hansard heading. That's
   the point. If nothing odd survives the innocent explanations, that's
   the answer too, and it's a good paragraph.

   Uses Trevor's first-article tables: dbo.speech, dbo.speech_vec,
   dbo.speech_sig, dbo.centroid. Commons only, about 70% of speeches,
   with the mid-2001 to 2004 gap. Step 3 is the slow one.
   ===================================================================== */
USE [HANSARD];
GO

DECLARE @min_chars   int = 400,    -- roughly 70 words: skip "Will the Minister give way?"
        @min_debate  int = 6,      -- need enough speeches to have a "normal"
        @max_debate  int = 150,
        @shortlist   int = 20000;  -- speeches carried into the pairwise step

/* ---------------------------------------------------------------------
   1. Debates and their substantive speeches
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #sp;
SELECT s.speech_id, s.speech_date, s.speaker_name, s.party,
       s.major_heading, s.minor_heading,
       Chars = LEN(s.body),
       g.cluster_id
INTO #sp
FROM dbo.speech AS s
JOIN dbo.speech_sig AS g ON g.speech_id = s.speech_id
JOIN dbo.speech_role AS r ON r.speech_id = s.speech_id
WHERE LEN(s.body) >= @min_chars
  AND s.major_heading IS NOT NULL
  AND r.role <> 'chair'
  AND s.speaker_name NOT LIKE N'%Speaker%'
  AND s.speaker_name NOT LIKE N'%Chairman%'
  -- 'Unknown' is division lists, resolutions and motions, not people
  AND s.speaker_name <> N'Unknown' AND s.party IS NOT NULL
  AND s.body NOT LIKE N'Division%' AND s.body NOT LIKE N'Divisoin%'
  AND s.body NOT LIKE N'%Tellers for the Ayes%'
  AND s.body NOT LIKE N'Resolved,%' AND s.body NOT LIKE N'Motion made%' AND s.body NOT LIKE N'Question put%'
  -- deputy speakers filed under their own names: calling time, not making speeches
  AND s.body NOT LIKE N'Order.%' AND s.body NOT LIKE N'%time limit%'
  AND s.body NOT LIKE N'With this it will be convenient%' AND s.body NOT LIKE N'I inform the House%'
  AND s.body NOT LIKE N'%Before I call%' AND s.body NOT LIKE N'We now come to%'
  -- open-ended slots where any topic is fair game
  AND s.major_heading NOT IN (N'Engagements', N'Business of the House', N'Points of Order',
                              N'Topical Questions', N'Business', N'Point of Order')
  AND ISNULL(s.minor_heading, N'') NOT IN (N'Engagements', N'Topical Questions', N'Business of the House');

-- each debate is named by its first speech_id
DROP TABLE IF EXISTS #deb;
SELECT DebateId = MIN(speech_id), speech_date, major_heading, minor_heading,
       Speeches = COUNT(*)
INTO #deb
FROM #sp
GROUP BY speech_date, major_heading, minor_heading
HAVING COUNT(*) BETWEEN @min_debate AND @max_debate;

ALTER TABLE #sp ADD DebateId int NULL;
UPDATE s SET DebateId = d.DebateId
FROM #sp AS s
JOIN #deb AS d ON d.speech_date = s.speech_date AND d.major_heading = s.major_heading
              AND ISNULL(d.minor_heading, N'') = ISNULL(s.minor_heading, N'');
DELETE #sp WHERE DebateId IS NULL;

-- Some debates appear twice in the source (1994-04-15 Merchant Shipping is one).
-- A speech with an exact copy has a nearest neighbour at distance 0, which wrecks the yardstick.
WITH d AS (SELECT s.speech_id,
                  rn = ROW_NUMBER() OVER (PARTITION BY s.speech_date, CHECKSUM(LEFT(b.body, 4000)) ORDER BY s.speech_id)
           FROM #sp AS s JOIN dbo.speech AS b ON b.speech_id = s.speech_id)
DELETE s FROM #sp AS s JOIN d ON d.speech_id = s.speech_id WHERE d.rn > 1;
CREATE CLUSTERED INDEX cx ON #sp (DebateId, speech_id);

/* ---------------------------------------------------------------------
   2. Distance from the debate's dominant cluster
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #dom;
SELECT DebateId, cluster_id, Share = CAST(n AS float) / total
INTO #dom
FROM (SELECT DebateId, cluster_id, n = COUNT(*),
             total = SUM(COUNT(*)) OVER (PARTITION BY DebateId),
             rk = ROW_NUMBER() OVER (PARTITION BY DebateId ORDER BY COUNT(*) DESC, cluster_id)
      FROM #sp GROUP BY DebateId, cluster_id) AS x
WHERE rk = 1;

DROP TABLE IF EXISTS #dist;
SELECT s.speech_id, s.DebateId, s.cluster_id, OwnCluster = CAST(CASE WHEN s.cluster_id = d.cluster_id THEN 1 ELSE 0 END AS bit),
       DomCluster = d.cluster_id, DomShare = d.Share,
       Dist = VECTOR_DISTANCE('cosine', v.embedding, c.embedding)
INTO #dist
FROM #sp AS s
JOIN #dom AS d ON d.DebateId = s.DebateId
JOIN dbo.speech_vec AS v ON v.speech_id = s.speech_id
JOIN dbo.centroid AS c ON c.cluster_id = d.cluster_id;

DROP TABLE IF EXISTS #z;
SELECT *, Z = (Dist - AVG(Dist) OVER (PARTITION BY DebateId))
              / NULLIF(STDEV(Dist) OVER (PARTITION BY DebateId), 0)
INTO #z
FROM #dist;

/* ---------------------------------------------------------------------
   3. Shortlist: how far is it from its nearest neighbour in the debate?
      Compared with how close the debate's other speeches are to theirs.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #short;
SELECT TOP (@shortlist) speech_id, DebateId, Z, Dist
INTO #short
FROM #z
WHERE OwnCluster = 0 AND DomShare >= 0.4      -- the debate has a clear topic, and this isn't it
ORDER BY Z DESC;

DROP TABLE IF EXISTS #nn;
SELECT k.speech_id,
       NearestDist = MIN(VECTOR_DISTANCE('cosine', a.embedding, b.embedding))
INTO #nn
FROM #short AS k
JOIN #sp AS o ON o.DebateId = k.DebateId AND o.speech_id <> k.speech_id
JOIN dbo.speech_vec AS a ON a.speech_id = k.speech_id
JOIN dbo.speech_vec AS b ON b.speech_id = o.speech_id
GROUP BY k.speech_id;

-- the yardstick: a typical speech's nearest neighbour in the same debates
DROP TABLE IF EXISTS #yard;
SELECT DebateId = x.DebateId, TypicalNN = AVG(x.nn)
INTO #yard
FROM (SELECT o.DebateId, o.speech_id,
             nn = MIN(VECTOR_DISTANCE('cosine', a.embedding, b.embedding))
      FROM (SELECT DISTINCT DebateId FROM #short) AS d
      JOIN #sp AS o  ON o.DebateId = d.DebateId
      JOIN #sp AS o2 ON o2.DebateId = o.DebateId AND o2.speech_id <> o.speech_id
      JOIN dbo.speech_vec AS a ON a.speech_id = o.speech_id
      JOIN dbo.speech_vec AS b ON b.speech_id = o2.speech_id
      WHERE o.speech_id NOT IN (SELECT speech_id FROM #short)
      GROUP BY o.DebateId, o.speech_id) AS x
GROUP BY x.DebateId;

DROP TABLE IF EXISTS #out;
SELECT k.speech_id, k.DebateId, k.Z, k.Dist, n.NearestDist, y.TypicalNN,
       Lonely = n.NearestDist / NULLIF(y.TypicalNN, 0),     -- 2.0 = twice as far from anything as normal
       Score  = k.Z * n.NearestDist / NULLIF(y.TypicalNN, 0)
INTO #out
FROM #short AS k
JOIN #nn   AS n ON n.speech_id = k.speech_id
JOIN #yard AS y ON y.DebateId = k.DebateId
WHERE y.TypicalNN >= 0.05;       -- a debate whose speeches are near-copies of each other has no yardstick

/* ---------------------------------------------------------------------
   4. Where it really belongs: the nearest centroid, and that cluster's
      usual heading
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #top;
SELECT TOP (300) * INTO #top FROM #out ORDER BY Score DESC;

DROP TABLE IF EXISTS #home;
SELECT t.speech_id, h.cluster_id, h.HomeDist
INTO #home
FROM #top AS t
JOIN dbo.speech_vec AS v ON v.speech_id = t.speech_id
CROSS APPLY (SELECT TOP (1) c.cluster_id, HomeDist = VECTOR_DISTANCE('cosine', v.embedding, c.embedding)
             FROM dbo.centroid AS c
             ORDER BY VECTOR_DISTANCE('cosine', v.embedding, c.embedding)) AS h;

DROP TABLE IF EXISTS #label;
SELECT cluster_id, Heading
INTO #label
FROM (SELECT g.cluster_id, Heading = s.major_heading,
             rk = ROW_NUMBER() OVER (PARTITION BY g.cluster_id ORDER BY COUNT(*) DESC)
      FROM dbo.speech_sig AS g
      JOIN dbo.speech AS s ON s.speech_id = g.speech_id
      WHERE g.cluster_id IN (SELECT cluster_id FROM #home UNION SELECT DomCluster FROM #z WHERE speech_id IN (SELECT speech_id FROM #top))
        AND s.major_heading IS NOT NULL
      GROUP BY g.cluster_id, s.major_heading) AS x
WHERE rk = 1;

/* ---------------------------------------------------------------------
   Results
   --------------------------------------------------------------------- */

-- A. The most out-of-place speeches. Read the extract against the debate title.
SELECT TOP (100)
       s.speech_date, s.speaker_name, s.party,
       Debate        = CONCAT(s.major_heading, N' / ' + s.minor_heading),
       DebateUsually = ld.Heading,
       SoundsLike    = lh.Heading,
       Z             = CAST(t.Z AS decimal(5,2)),
       Lonely        = CAST(t.Lonely AS decimal(5,2)),
       Words         = LEN(s.body) / 6,
       Extract       = LEFT(s.body, 400),
       s.url
FROM #top AS t
JOIN dbo.speech AS s ON s.speech_id = t.speech_id
JOIN #z     AS z  ON z.speech_id = t.speech_id
JOIN #home  AS h  ON h.speech_id = t.speech_id
LEFT JOIN #label AS ld ON ld.cluster_id = z.DomCluster
LEFT JOIN #label AS lh ON lh.cluster_id = h.cluster_id
ORDER BY t.Score DESC;

-- B. Who does it most? Out-of-place speeches per 1,000 substantive speeches.
--    A speaker near the top is either a crank, a comedian, or worth a closer look.
SELECT TOP (40)
       s.speaker_name,
       Speeches   = COUNT(*),
       OutOfPlace = SUM(CASE WHEN o.speech_id IS NOT NULL AND o.Lonely >= 1.5 THEN 1 ELSE 0 END),
       Per1000    = CAST(1000.0 * SUM(CASE WHEN o.speech_id IS NOT NULL AND o.Lonely >= 1.5 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(6,2))
FROM #sp AS s
LEFT JOIN #out AS o ON o.speech_id = s.speech_id
GROUP BY s.speaker_name
HAVING COUNT(*) >= 200
ORDER BY Per1000 DESC;

-- C. By year. A spike in a quiet year is more interesting than a steady background.
--    Remember the 2001-04 gap in dbo.speech.
SELECT Yr = YEAR(s.speech_date),
       Speeches   = COUNT(*),
       OutOfPlace = SUM(CASE WHEN o.Lonely >= 1.5 THEN 1 ELSE 0 END),
       Per10000   = CAST(10000.0 * SUM(CASE WHEN o.Lonely >= 1.5 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(6,2))
FROM #sp AS s
LEFT JOIN #out AS o ON o.speech_id = s.speech_id
GROUP BY YEAR(s.speech_date)
ORDER BY Yr;

-- D. The same speaker, the same odd topic, in unrelated debates.
--    One stray speech is a tangent. A repeated one is a habit, or a signal.
SELECT s.speaker_name, SoundsLike = lh.Heading,
       Times = COUNT(*),
       Debates = STRING_AGG(CAST(CONCAT(FORMAT(s.speech_date, 'yyyy-MM-dd'), N' ', s.major_heading) AS nvarchar(max)), N' | ')
                 WITHIN GROUP (ORDER BY s.speech_date)
FROM #top AS t
JOIN dbo.speech AS s ON s.speech_id = t.speech_id
JOIN #home AS h ON h.speech_id = t.speech_id
LEFT JOIN #label AS lh ON lh.cluster_id = h.cluster_id
GROUP BY s.speaker_name, lh.Heading
HAVING COUNT(*) >= 2
ORDER BY Times DESC;
GO
