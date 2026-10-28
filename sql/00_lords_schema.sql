/* =====================================================================
   House of Lords  -  slice 2 of the Hansard series
   00_lords_schema.sql : the tables python/load_lords.py fills.

   hl.SourceSpeech  every Lords speech and procedural line from the
                    TheyWorkForYou / ParlParse daily XML (1999 on), in
                    sitting order. Same shape as hc.SourceSpeech, so the
                    Commons code can be pointed at it with little change.
   hl.Person        everyone in ParlParse people.json who sat in either
                    House, with their data.parliament (Members API) id.
   hl.PersonName    every form of their name, for matching Odell's DisplayAs.
   hl.Membership    each seat they held: Commons or Lords, party, and for
                    peers the peerage type (L life, HP/HD/HO hereditary,
                    B bishop, A law lord). Dates as people.json gives them.
   hl.Division      Lords divisions, straight out of the same XML.
   hl.Vote          how each peer voted in them.

   Run this once, then python/load_lords.py, then 01_lords_views.sql.
   ===================================================================== */
USE [HANSARD];
GO

IF SCHEMA_ID('hl') IS NULL EXEC('CREATE SCHEMA hl');
GO

IF OBJECT_ID('hl.SourceSpeech') IS NULL
CREATE TABLE hl.SourceSpeech
(
    Id           bigint        IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Gid          varchar(100)  NOT NULL UNIQUE,       -- uk.org.publicwhip/lords/2010-01-12a.123.4
    SittingDate  date          NOT NULL,
    Seq          bigint        NOT NULL,              -- position in the day's file: the true sitting order
    Location     varchar(10)   NOT NULL,              -- Chamber | GC (Grand Committee) | other column prefix
    ColNum       varchar(20)   NULL,                  -- Hansard column as printed, e.g. 123 or GC45
    SpokenAt     varchar(10)   NULL,                  -- time stamp where Hansard gives one
    SpeechClass  varchar(20)   NULL,                  -- Speech | Procedural
    SpeakerName  nvarchar(400) NULL,                  -- as printed: 'The Lord Speaker (Baroness Hayman)'
    PersonId     nvarchar(100) NULL,                  -- uk.org.publicwhip/person/10544, same ids as Odell
    LordId       nvarchar(100) NULL,                  -- uk.org.publicwhip/lord/100xxx, older files only
    MajorHeading nvarchar(400) NULL,
    MinorHeading nvarchar(400) NULL,
    Body         nvarchar(max) NULL,
    INDEX ix_day (SittingDate, Seq),
    INDEX ix_person (PersonId)
);
GO

IF OBJECT_ID('hl.Person') IS NULL
CREATE TABLE hl.Person
(
    PersonId      nvarchar(100) NOT NULL PRIMARY KEY,
    DataParlId    int           NULL,                 -- Members API id (members-api.parliament.uk)
    DisplayName   nvarchar(400) NULL,                 -- 'Lord Smith of Finsbury' or 'Chris Smith'
    GivenName     nvarchar(200) NULL,
    Surname       nvarchar(200) NULL
);
GO

-- rebuilt every time: it is derived from people.json, and has no primary key on
-- purpose, because SQL Server's collation sees 'Mcavoy' = 'McAvoy' and more besides
DROP TABLE IF EXISTS hl.PersonName;
CREATE TABLE hl.PersonName
(
    PersonId      nvarchar(100) NOT NULL,
    Name          nvarchar(400) NOT NULL,             -- every written form: 'Paddy Ashdown', 'Jeremy Ashdown'...
    INDEX ix_name CLUSTERED (Name, PersonId)
);
GO

IF OBJECT_ID('hl.Membership') IS NULL
CREATE TABLE hl.Membership
(
    MembershipId  nvarchar(100) NOT NULL PRIMARY KEY, -- .../lord/100867 or .../member/2069
    PersonId      nvarchar(100) NOT NULL,
    House         varchar(10)   NOT NULL,             -- Commons | Lords
    PeerageType   varchar(4)    NULL,                 -- L, HP, HD, HO, B, A (Lords only)
    Party         nvarchar(100) NULL,                 -- people.json organisation id: labour, crossbench, bishop...
    Constituency  nvarchar(200) NULL,                 -- Commons only
    StartDate     date          NULL,
    EndDate       date          NULL,                 -- NULL = still sitting
    StartReason   varchar(50)   NULL,
    EndReason     varchar(50)   NULL,                 -- died, retired, changed_party, general_election...
    INDEX ix_person (PersonId, House, StartDate)
);
GO

IF OBJECT_ID('hl.Division') IS NULL
CREATE TABLE hl.Division
(
    DivisionGid   varchar(100)  NOT NULL PRIMARY KEY,
    SittingDate   date          NOT NULL,
    DivNumber     int           NULL,
    Seq           bigint        NOT NULL,             -- same scale as hl.SourceSpeech.Seq
    MajorHeading  nvarchar(400) NULL,
    MinorHeading  nvarchar(400) NULL,
    Contents      int           NULL,                 -- as Hansard reports the count
    NotContents   int           NULL
);
GO

IF OBJECT_ID('hl.Vote') IS NULL
CREATE TABLE hl.Vote
(
    DivisionGid   varchar(100)  NOT NULL,
    PersonId      nvarchar(100) NULL,
    LordId        nvarchar(100) NULL,
    PrintedName   nvarchar(400) NULL,
    Vote          varchar(20)   NOT NULL,             -- content | not-content
    Teller        bit           NOT NULL DEFAULT 0,
    INDEX ix_div (DivisionGid),
    INDEX ix_person (PersonId)
);
GO
