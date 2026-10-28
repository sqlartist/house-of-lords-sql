/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   06_chamber.sql : the Commons chamber as TV graphics, built in SQL.

   One dot per MP returned at each general election since 1979, on the
   real layout: the Speaker's chair at the end, the government benches
   on the Speaker's right, the opposition facing them across the floor,
   five rows deep, filling from the Speaker's end.

   hl.ElectedMP       who was elected at each election, and their party
   hl.ChamberSeat     each MP's seat: x/y, side, and a geometry dot
   hl.fnChamberSvg()  the whole chamber for one election as an SVG,
                      in real party colours, ready for a web page

   Party: people.json has it from 1997 on. Before that it comes from
   the party Odell's data gives the MP in the year after the election,
   via hl.CommonsName. MPs who never spoke that year stay grey.

   Needs 01 and 02 run. In SSMS, run the last query and open the
   "Spatial results" tab to see the chamber.
   ===================================================================== */
USE [HANSARD];
GO

/* ---------------------------------------------------------------------
   Parties, the way a results programme groups them
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS hl.PartyStyle;
CREATE TABLE hl.PartyStyle (Grp varchar(10) PRIMARY KEY, Label nvarchar(40), Colour char(7), SortKey int);
INSERT hl.PartyStyle VALUES
    ('CON', N'Conservative',     '#0087DC', 1),
    ('LAB', N'Labour',           '#E4003B', 2),
    ('LD',  N'Liberal Democrat', '#FAA61A', 3),
    ('ALL', N'SDP-Liberal Alliance', '#FFD700', 3),
    ('SNP', N'SNP',              '#FDF38E', 4),
    ('PC',  N'Plaid Cymru',      '#005B54', 5),
    ('REF', N'Reform UK',        '#12B6CF', 6),
    ('GRN', N'Green',            '#6AB023', 7),
    ('NI',  N'Northern Ireland', '#7A5C99', 8),
    ('OTH', N'Other',            '#999999', 9),
    ('SPK', N'Speaker and deputies', '#FFFFFF', 0),
    ('UNK', N'Not known',        '#555555', 10);
GO

CREATE OR ALTER FUNCTION hl.fnPartyGroup (@party nvarchar(200), @on date)
RETURNS varchar(10)
AS
BEGIN
    DECLARE @p nvarchar(200) = REPLACE(LOWER(ISNULL(@party, N'')), N'-', N' ');
    RETURN CASE
        WHEN @p = N''                                   THEN 'UNK'
        WHEN @p LIKE N'%speaker%'                       THEN 'SPK'   -- people.json files deputies as 'deputy-speaker'
        WHEN @p LIKE N'%social democratic and labour%' OR @p = N'sdlp' THEN 'NI'   -- before Labour: SDLP contains 'labour'
        WHEN @p LIKE N'%conservative%'                  THEN 'CON'
        WHEN @p LIKE N'%labour%'                        THEN 'LAB'
        WHEN @p LIKE N'%liberal democrat%'              THEN 'LD'
        WHEN @p LIKE N'%social democrat%' OR @p = N'sdp'
          OR (@p LIKE N'%liberal%' AND @on < '1988-03-03') THEN 'ALL'
        WHEN @p LIKE N'%liberal%'                       THEN 'LD'
        WHEN @p LIKE N'%scottish national%' OR @p = N'snp' THEN 'SNP'
        WHEN @p LIKE N'%plaid%'                         THEN 'PC'
        WHEN @p LIKE N'%reform%'                        THEN 'REF'
        WHEN @p LIKE N'%green%'                         THEN 'GRN'
        WHEN @p LIKE N'%unionist%' OR @p IN (N'uup', N'dup', N'ukup', N'sdlp', N'tuv', N'alliance')
          OR @p LIKE N'%sinn%' OR @p LIKE N'%social democratic and labour%' OR @p LIKE N'%ulster%' THEN 'NI'
        ELSE 'OTH' END;
END;
GO

/* ---------------------------------------------------------------------
   Who was elected, election by election
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS hl.ElectedMP, #odell;

-- The party Odell gives each person, by year. Built once into a temp table:
-- as a CTE inside the OUTER APPLY below it was re-run for every MP.
SELECT c.PersonId, c.Yr, Party = MAX(s.Party)
INTO #odell
FROM hl.CommonsName AS c
JOIN hc.SourceSpeech AS s
  ON s.DisplayAs = c.DisplayAs COLLATE Latin1_General_100_CI_AS_SC_UTF8
 AND s.SittingDate >= DATEFROMPARTS(c.Yr, 1, 1) AND s.SittingDate < DATEFROMPARTS(c.Yr + 1, 1, 1)
WHERE s.Party IS NOT NULL
  AND c.Yr IN (SELECT YEAR(StartDate) FROM hl.Membership
               WHERE House = 'Commons' AND StartReason = 'general_election' AND StartDate BETWEEN '1979-01-01' AND '1996-12-31'
               UNION SELECT YEAR(StartDate) + 1 FROM hl.Membership
               WHERE House = 'Commons' AND StartReason = 'general_election' AND StartDate BETWEEN '1979-01-01' AND '1996-12-31')
GROUP BY c.PersonId, c.Yr;
CREATE CLUSTERED INDEX cx ON #odell (PersonId, Yr);

WITH elections AS (
    SELECT Election = StartDate
    FROM hl.Membership
    WHERE House = 'Commons' AND StartReason = 'general_election' AND StartDate >= '1979-01-01'
    GROUP BY StartDate HAVING COUNT(*) > 500
)
SELECT e.Election, m.PersonId, m.Constituency, p.DisplayName,
       PartySource = CASE WHEN m.Party IS NOT NULL THEN 'people.json' WHEN o.Party IS NOT NULL THEN 'Odell' END,
       Grp = hl.fnPartyGroup(COALESCE(m.Party, o.Party), e.Election)
INTO hl.ElectedMP
FROM elections AS e
JOIN hl.Membership AS m ON m.House = 'Commons' AND m.StartReason = 'general_election' AND m.StartDate = e.Election
JOIN hl.Person AS p ON p.PersonId = m.PersonId
OUTER APPLY (SELECT TOP (1) Party FROM #odell AS o
             WHERE m.Party IS NULL AND o.PersonId = m.PersonId AND o.Yr BETWEEN YEAR(e.Election) AND YEAR(e.Election) + 1
             ORDER BY o.Yr) AS o;
GO

-- Check against the published results before drawing anything
SELECT Election, Grp, Seats = COUNT(*)
FROM hl.ElectedMP GROUP BY Election, Grp ORDER BY Election, Seats DESC;

/* ---------------------------------------------------------------------
   Seats. Government parties sit on the Speaker's right (y > 0), the
   rest opposite (y < 0); the largest party on each side sits nearest
   the Speaker. Seat k on a side goes to column k / 5, row k % 5.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS hl.ChamberSeat;
WITH gov AS (
    SELECT e.Election, Grp = 'CON' FROM (SELECT DISTINCT Election FROM hl.ElectedMP) AS e
    WHERE e.Election < '1997-01-01' OR e.Election BETWEEN '2010-01-01' AND '2024-01-01'
    UNION ALL
    SELECT DISTINCT Election, 'LAB' FROM hl.ElectedMP
    WHERE Election BETWEEN '1997-01-01' AND '2009-12-31' OR Election >= '2024-01-01'
    UNION ALL
    SELECT DISTINCT Election, 'LD' FROM hl.ElectedMP WHERE Election BETWEEN '2010-01-01' AND '2010-12-31'
),
sized AS (
    SELECT m.Election, m.Grp, m.PersonId, m.DisplayName, m.Constituency,
           Side = CASE WHEN m.Grp = 'SPK' THEN 0 WHEN g.Grp IS NOT NULL THEN 1 ELSE -1 END,
           PartySize = COUNT(*) OVER (PARTITION BY m.Election, m.Grp)
    FROM hl.ElectedMP AS m
    LEFT JOIN gov AS g ON g.Election = m.Election AND g.Grp = m.Grp
),
placed AS (
    SELECT *, k = ROW_NUMBER() OVER (PARTITION BY Election, Side
                                     ORDER BY CASE WHEN Grp = 'UNK' THEN 1 ELSE 0 END, PartySize DESC, Grp, DisplayName) - 1
    FROM sized
)
SELECT Election, Grp, PersonId, DisplayName, Constituency, Side, k,
       X = CASE WHEN Side = 0 THEN -4.0 ELSE k / 5 * 1.0 END,
       Y = CASE WHEN Side = 0 THEN 0.0 ELSE Side * (2.0 + k % 5) END,
       Shape = geometry::Point(CASE WHEN Side = 0 THEN -4.0 ELSE k / 5 * 1.0 END,
                               CASE WHEN Side = 0 THEN 0.0 ELSE Side * (2.0 + k % 5) END, 0).STBuffer(0.42)
INTO hl.ChamberSeat
FROM placed;
GO

/* ---------------------------------------------------------------------
   The chamber as SVG, in party colours: one string per election.
   Paste it into a file ending .svg, or let the web page read them all.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION hl.fnChamberSvg (@election date)
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @cols int = (SELECT MAX(k) / 5 + 1 FROM hl.ChamberSeat WHERE Election = @election AND Side <> 0);
    DECLARE @w int = (@cols + 8) * 12, @h int = 16 * 12;
    RETURN CONCAT(
        N'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', @w, N' ', @h, N'" style="background:#0b1020">',
        N'<rect x="60" y="88" width="', @cols * 12, N'" height="16" fill="#2a3150"/>',       -- the floor and the Table
        (SELECT STRING_AGG(CAST(CONCAT(
                    N'<circle cx="', CAST(70 + s.X * 12 AS decimal(9,1)),
                    N'" cy="', CAST(96 - s.Y * 12 AS decimal(9,1)),
                    N'" r="5" fill="', ps.Colour, N'"><title>', s.DisplayName, N' (', ps.Label, N')</title></circle>')
                 AS nvarchar(max)), N'') WITHIN GROUP (ORDER BY s.Side, s.k)
         FROM hl.ChamberSeat AS s JOIN hl.PartyStyle AS ps ON ps.Grp = s.Grp
         WHERE s.Election = @election),
        N'<text x="10" y="20" fill="#fff" font-family="Arial" font-size="14">General election ',
        FORMAT(@election, 'd MMMM yyyy'), N'</text></svg>');
END;
GO

-- Seat counts per party per election, for the animated page
SELECT Election, Grp, Seats = COUNT(*)
FROM hl.ChamberSeat GROUP BY Election, Grp
ORDER BY Election, Grp
FOR JSON PATH;

-- One SVG per election
SELECT Election = CAST(Election AS varchar(10)), Svg = hl.fnChamberSvg(Election)
FROM (SELECT DISTINCT Election FROM hl.ChamberSeat) AS e ORDER BY Election;

-- SSMS: run this, then open the "Spatial results" tab (Label column: Grp)
SELECT Shape, Grp, DisplayName FROM hl.ChamberSeat WHERE Election = '1997-05-01';
GO
