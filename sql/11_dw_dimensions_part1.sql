USE PayerPulse;

-- Do member attributes stay the same across the three years? (expect 0s if so)
SELECT COUNT(*) AS members,
       SUM(CASE WHEN n_birth > 1 THEN 1 ELSE 0 END) AS multi_birth_date,
       SUM(CASE WHEN n_sex   > 1 THEN 1 ELSE 0 END) AS multi_sex,
       SUM(CASE WHEN n_race  > 1 THEN 1 ELSE 0 END) AS multi_race,
       SUM(CASE WHEN n_death > 1 THEN 1 ELSE 0 END) AS multi_death_date
FROM (
    SELECT desynpuf_id, COUNT(DISTINCT birth_date) AS n_birth, COUNT(DISTINCT sex_code) AS n_sex,
           COUNT(DISTINCT race_code) AS n_race, COUNT(DISTINCT death_date) AS n_death
    FROM stg.beneficiary GROUP BY desynpuf_id
) x;

-- Carrier claims whose member is missing from the beneficiary files (we haven't checked carrier yet; expect 0)
SELECT COUNT_BIG(*) AS carrier_orphans
FROM stg.carrier_claim c
WHERE NOT EXISTS (SELECT 1 FROM stg.beneficiary b WHERE b.desynpuf_id = c.desynpuf_id);

USE PayerPulse;
GO

/* ---------- dim_date: one row per calendar day, 2007-2011 ---------- */
IF OBJECT_ID(N'dw.dim_date', N'U') IS NULL
CREATE TABLE dw.dim_date (
    date_key         INT         NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,   -- yyyymmdd
    full_date        DATE        NOT NULL CONSTRAINT UQ_dim_date_full_date UNIQUE,
    calendar_year    SMALLINT    NOT NULL,
    calendar_quarter TINYINT     NOT NULL,
    calendar_month   TINYINT     NOT NULL,
    month_name       VARCHAR(10) NOT NULL,
    year_month       CHAR(7)     NOT NULL,                                      -- yyyy-mm
    day_of_month     TINYINT     NOT NULL,
    day_of_week      TINYINT     NOT NULL,
    is_weekend       BIT         NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM dw.dim_date)
BEGIN
    ;WITH d AS (
        SELECT CAST('2007-01-01' AS DATE) AS dt
        UNION ALL
        SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2011-12-31'
    )
    INSERT INTO dw.dim_date (date_key, full_date, calendar_year, calendar_quarter, calendar_month,
                             month_name, year_month, day_of_month, day_of_week, is_weekend)
    SELECT CONVERT(INT, CONVERT(CHAR(8), dt, 112)), dt, YEAR(dt), DATEPART(QUARTER, dt), MONTH(dt),
           DATENAME(MONTH, dt), CONVERT(CHAR(7), dt, 120), DAY(dt), DATEPART(WEEKDAY, dt),
           CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
    FROM d
    OPTION (MAXRECURSION 0);
END
GO

/* ---------- dim_beneficiary: one row per member ---------- */
IF OBJECT_ID(N'dw.dim_beneficiary', N'U') IS NULL
CREATE TABLE dw.dim_beneficiary (
    beneficiary_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_beneficiary PRIMARY KEY,
    desynpuf_id     VARCHAR(16) NOT NULL CONSTRAINT UQ_dim_beneficiary_id UNIQUE,   -- business key
    birth_date      DATE        NULL,
    death_date      DATE        NULL,
    sex_code        CHAR(1)     NULL,
    sex_desc        VARCHAR(10) NULL,
    race_code       CHAR(1)     NULL,
    race_desc       VARCHAR(10) NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM dw.dim_beneficiary)
INSERT INTO dw.dim_beneficiary (desynpuf_id, birth_date, death_date, sex_code, sex_desc, race_code, race_desc)
SELECT desynpuf_id, birth_date, death_date_any, sex_code,
       CASE sex_code WHEN '1' THEN 'Male' WHEN '2' THEN 'Female' END,
       race_code,
       CASE race_code WHEN '1' THEN 'White' WHEN '2' THEN 'Black' WHEN '3' THEN 'Other' WHEN '5' THEN 'Hispanic' END
FROM (
    SELECT b.desynpuf_id, b.birth_date, b.sex_code, b.race_code,
           MAX(b.death_date) OVER (PARTITION BY b.desynpuf_id) AS death_date_any,
           ROW_NUMBER() OVER (PARTITION BY b.desynpuf_id ORDER BY b.coverage_year DESC) AS rn
    FROM stg.beneficiary b
) x
WHERE rn = 1;
GO

/* ---------- dim_provider: facilities (PRVDR_NUM) and physicians (NPI) ---------- */
IF OBJECT_ID(N'dw.dim_provider', N'U') IS NULL
CREATE TABLE dw.dim_provider (
    provider_key     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_provider PRIMARY KEY,
    provider_id      VARCHAR(20) NOT NULL,
    provider_id_type VARCHAR(10) NOT NULL,   -- FACILITY or NPI
    CONSTRAINT UQ_dim_provider UNIQUE (provider_id_type, provider_id),
    CONSTRAINT CK_dim_provider_type CHECK (provider_id_type IN ('FACILITY','NPI'))
);
GO
IF NOT EXISTS (SELECT 1 FROM dw.dim_provider)
INSERT INTO dw.dim_provider (provider_id, provider_id_type)
SELECT provider_id, provider_id_type
FROM (
    SELECT prvdr_num AS provider_id, 'FACILITY' AS provider_id_type FROM stg.inpatient_claim  WHERE prvdr_num IS NOT NULL
    UNION SELECT prvdr_num,    'FACILITY' FROM stg.outpatient_claim WHERE prvdr_num IS NOT NULL
    UNION SELECT at_physn_npi, 'NPI' FROM stg.inpatient_claim  WHERE at_physn_npi IS NOT NULL
    UNION SELECT op_physn_npi, 'NPI' FROM stg.inpatient_claim  WHERE op_physn_npi IS NOT NULL
    UNION SELECT ot_physn_npi, 'NPI' FROM stg.inpatient_claim  WHERE ot_physn_npi IS NOT NULL
    UNION SELECT at_physn_npi, 'NPI' FROM stg.outpatient_claim WHERE at_physn_npi IS NOT NULL
    UNION SELECT op_physn_npi, 'NPI' FROM stg.outpatient_claim WHERE op_physn_npi IS NOT NULL
    UNION SELECT ot_physn_npi, 'NPI' FROM stg.outpatient_claim WHERE ot_physn_npi IS NOT NULL
    UNION SELECT prf_physn_npi,'NPI' FROM stg.carrier_line     WHERE prf_physn_npi IS NOT NULL
) p;
GO

/* ---------- dim_drg ---------- */
IF OBJECT_ID(N'dw.dim_drg', N'U') IS NULL
CREATE TABLE dw.dim_drg (
    drg_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_drg PRIMARY KEY,
    drg_code       VARCHAR(10) NOT NULL CONSTRAINT UQ_dim_drg_code UNIQUE,
    is_placeholder BIT         NOT NULL,      -- 'OTH' = suppressed/other, excluded from DRG-level KPIs
    description    VARCHAR(300) NULL          -- filled later from a public DRG reference if we add one
);
GO
IF NOT EXISTS (SELECT 1 FROM dw.dim_drg)
INSERT INTO dw.dim_drg (drg_code, is_placeholder)
SELECT DISTINCT clm_drg_cd, CASE WHEN clm_drg_cd = 'OTH' THEN 1 ELSE 0 END
FROM stg.inpatient_claim WHERE clm_drg_cd IS NOT NULL;
GO

/* ---------- dim_ndc (Part D drugs) ---------- */
IF OBJECT_ID(N'dw.dim_ndc', N'U') IS NULL
CREATE TABLE dw.dim_ndc (
    ndc_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_ndc PRIMARY KEY,
    ndc_code       VARCHAR(11)  NOT NULL CONSTRAINT UQ_dim_ndc_code UNIQUE,
    is_placeholder BIT          NOT NULL,     -- 'OTHER'
    drug_name      VARCHAR(200) NULL,         -- needs an external NDC reference file (not in DE-SynPUF)
    is_generic     BIT          NULL          -- same: only filled if we add a mapping
);
GO
IF NOT EXISTS (SELECT 1 FROM dw.dim_ndc)
INSERT INTO dw.dim_ndc (ndc_code, is_placeholder)
SELECT DISTINCT ndc_code, CASE WHEN ndc_code = 'OTHER' THEN 1 ELSE 0 END
FROM stg.pde_event WHERE ndc_code IS NOT NULL;
GO

SELECT 'dim_date' AS dim, COUNT(*) AS loaded, 1826 AS expected FROM dw.dim_date
UNION ALL SELECT 'dim_beneficiary', COUNT(*), (SELECT COUNT(DISTINCT desynpuf_id) FROM stg.beneficiary) FROM dw.dim_beneficiary
UNION ALL SELECT 'dim_drg',  COUNT(*), (SELECT COUNT(DISTINCT clm_drg_cd) FROM stg.inpatient_claim) FROM dw.dim_drg
UNION ALL SELECT 'dim_ndc',  COUNT(*), (SELECT COUNT(DISTINCT ndc_code) FROM stg.pde_event) FROM dw.dim_ndc
UNION ALL SELECT 'dim_provider', COUNT(*), NULL FROM dw.dim_provider;

SELECT provider_id_type, COUNT(*) AS n FROM dw.dim_provider GROUP BY provider_id_type;
SELECT TOP 5 * FROM dw.dim_beneficiary;

;WITH v AS (
    SELECT 'dim_date' AS dim, COUNT(*) AS loaded, 1826 AS expected FROM dw.dim_date
    UNION ALL SELECT 'dim_beneficiary', COUNT(*), (SELECT COUNT(DISTINCT desynpuf_id) FROM stg.beneficiary) FROM dw.dim_beneficiary
    UNION ALL SELECT 'dim_drg', COUNT(*), (SELECT COUNT(DISTINCT clm_drg_cd) FROM stg.inpatient_claim) FROM dw.dim_drg
    UNION ALL SELECT 'dim_ndc', COUNT(*), (SELECT COUNT(DISTINCT ndc_code) FROM stg.pde_event) FROM dw.dim_ndc
)
INSERT INTO audit.load_log (pipeline_step, source_file, finished_at, rows_read, rows_loaded, status)
SELECT 'dw_dim_load', dim, SYSUTCDATETIME(), expected, loaded,
       CASE WHEN loaded = expected THEN 'SUCCESS' ELSE 'FAILED' END
FROM v;

SELECT TOP 4 * FROM audit.load_log ORDER BY load_id DESC;