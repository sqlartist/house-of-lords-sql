/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   01_lords_views.sql : the views to work from, and a first look.
   Run after python/load_lords.py.

   hl.vSpeech     each Lords speech with the peer's party and peerage
                  type on the day, and whether they had been an MP.
   hl.vPeer       one row per peer: how they got there, when, and
                  their Commons career if they had one.
   ===================================================================== */
USE [HANSARD];
GO

/* the Lords seat that was current on a given day (a peer who changes
   party gets a new membership row, so this picks the right party) */
CREATE OR ALTER FUNCTION hl.fnSeatOn (@PersonId nvarchar(100), @On date)
RETURNS TABLE
AS RETURN
SELECT TOP (1) m.Party, m.PeerageType, m.StartDate
FROM hl.Membership AS m
WHERE m.PersonId = @PersonId AND m.House = 'Lords'
  AND (m.StartDate IS NULL OR m.StartDate <= @On)
  AND (m.EndDate   IS NULL OR m.EndDate   >= @On)
ORDER BY m.StartDate DESC;
GO

CREATE OR ALTER VIEW hl.vPeer
AS
SELECT p.PersonId, p.DataParlId, p.DisplayName,
       PeerageType  = l.PeerageType,               -- of their first Lords seat
       FirstSat     = l.FirstSat,
       LastSat      = l.LastSat,                   -- NULL = still a member
       ExMP         = CAST(CASE WHEN c.PersonId IS NOT NULL THEN 1 ELSE 0 END AS bit),
       CommonsFrom  = c.FirstSat,
       CommonsTo    = c.LastSat
FROM hl.Person AS p
CROSS APPLY (SELECT TOP (1) PeerageType,
                    FirstSat = MIN(StartDate) OVER (),
                    LastSat  = CASE WHEN COUNT(*) OVER () > COUNT(EndDate) OVER () THEN NULL
                                    ELSE MAX(EndDate) OVER () END
             FROM hl.Membership WHERE PersonId = p.PersonId AND House = 'Lords'
             ORDER BY StartDate) AS l
OUTER APPLY (SELECT PersonId = MIN(PersonId), FirstSat = MIN(StartDate), LastSat = MAX(EndDate)
             FROM hl.Membership WHERE PersonId = p.PersonId AND House = 'Commons'
             HAVING COUNT(*) > 0) AS c;
GO

CREATE OR ALTER VIEW hl.vSpeech
AS
SELECT
    SpeechId     = s.Id,
    s.SittingDate, s.Seq, s.Location, s.SpeechClass,
    MajorHeading = TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM s.MajorHeading),
    MinorHeading = TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM s.MinorHeading),
    s.SpeakerName, s.PersonId,
    Party        = seat.Party,
    PeerageType  = seat.PeerageType,
    ExMP         = pr.ExMP,
    s.Body
FROM hl.SourceSpeech AS s
OUTER APPLY hl.fnSeatOn(s.PersonId, s.SittingDate) AS seat
LEFT JOIN hl.vPeer AS pr ON pr.PersonId = s.PersonId;
GO

/* ---------------------------------------------------------------------
   First look. Run these before anything else.
   --------------------------------------------------------------------- */

-- 1. Coverage: sitting days and speeches per year (gaps mean missing files)
SELECT Yr = YEAR(SittingDate), Days = COUNT(DISTINCT SittingDate),
       Speeches = SUM(CASE WHEN SpeechClass = 'Speech' THEN 1 ELSE 0 END),
       GrandCommittee = SUM(CASE WHEN Location = 'GC' THEN 1 ELSE 0 END)
FROM hl.SourceSpeech GROUP BY YEAR(SittingDate) ORDER BY Yr;

-- 2. Speeches with no person attached (the Chair, "Noble Lords", unmatched names)
SELECT TOP (50) SpeakerName, N = COUNT(*)
FROM hl.SourceSpeech
WHERE PersonId IS NULL AND SpeechClass = 'Speech'
GROUP BY SpeakerName ORDER BY N DESC;

-- 3. Who presides: the Chair's printed titles over time
SELECT Title = LEFT(SpeakerName, CHARINDEX(N'(', SpeakerName + N'(') - 1),
       FirstSeen = MIN(SittingDate), LastSeen = MAX(SittingDate), N = COUNT(*)
FROM hl.SourceSpeech
WHERE SpeakerName LIKE N'The Lord Speaker%' OR SpeakerName LIKE N'The Lord Chancellor%'
   OR SpeakerName LIKE N'The Deputy Speaker%' OR SpeakerName LIKE N'The Deputy Chairman%'
   OR SpeakerName LIKE N'The Chairman of Committees%'
GROUP BY LEFT(SpeakerName, CHARINDEX(N'(', SpeakerName + N'(') - 1)
ORDER BY FirstSeen;

-- 4. The House by peerage type and party, on the floor (speeches, not seats)
SELECT PeerageType, Party, Speeches = COUNT(*), Peers = COUNT(DISTINCT PersonId)
FROM hl.vSpeech WHERE SpeechClass = 'Speech' AND PersonId IS NOT NULL
GROUP BY PeerageType, Party ORDER BY Speeches DESC;

-- 5. MPs who became peers: how much they speak in each House
SELECT TOP (50) p.DisplayName, p.CommonsFrom, p.CommonsTo, p.FirstSat,
       LordsSpeeches = (SELECT COUNT(*) FROM hl.SourceSpeech AS s
                        WHERE s.PersonId = p.PersonId AND s.SpeechClass = 'Speech'),
       CommonsSpeeches = (SELECT COUNT(*) FROM hc.SourceSpeech AS c
                          WHERE c.PersonId = p.PersonId)   -- needs the Commons full source loaded
FROM hl.vPeer AS p
WHERE p.ExMP = 1
ORDER BY LordsSpeeches DESC;

-- 6. Divisions: count check against Hansard's own totals
SELECT TOP (20) d.SittingDate, d.DivNumber, d.Contents, d.NotContents,
       Listed = (SELECT COUNT(*) FROM hl.Vote AS v WHERE v.DivisionGid = d.DivisionGid),
       Unmatched = (SELECT COUNT(*) FROM hl.Vote AS v WHERE v.DivisionGid = d.DivisionGid AND v.PersonId IS NULL)
FROM hl.Division AS d
ORDER BY ABS(ISNULL(d.Contents, 0) + ISNULL(d.NotContents, 0)
             - (SELECT COUNT(*) FROM hl.Vote AS v WHERE v.DivisionGid = d.DivisionGid)) DESC;
GO
