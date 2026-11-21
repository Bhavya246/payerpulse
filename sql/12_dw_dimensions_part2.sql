USE PayerPulse;
GO

/* ---------- dim_diagnosis: every distinct ICD-9-CM diagnosis code seen on any claim ---------- */
IF OBJECT_ID(N'dw.dim_diagnosis', N'U') IS NULL
CREATE TABLE dw.dim_diagnosis (
    diagnosis_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_diagnosis PRIMARY KEY,
    icd9_code     VARCHAR(10)  NOT NULL CONSTRAINT UQ_dim_diagnosis_code UNIQUE,
    description   VARCHAR(300) NULL          -- filled later from a public ICD-9 reference if we add one
);
GO

DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME(), @n BIGINT;
IF NOT EXISTS (SELECT 1 FROM dw.dim_diagnosis)
BEGIN
    INSERT INTO dw.dim_diagnosis (icd9_code)
    SELECT dx FROM (
        SELECT v.dx FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.admtng_icd9_dgns_cd), (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8), (c.icd9_dgns_cd_9), (c.icd9_dgns_cd_10)) AS v(dx)
        UNION
        SELECT v.dx FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.admtng_icd9_dgns_cd), (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8), (c.icd9_dgns_cd_9), (c.icd9_dgns_cd_10)) AS v(dx)
        UNION
        SELECT v.dx FROM stg.carrier_claim c CROSS APPLY (VALUES (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8)) AS v(dx)
        UNION
        SELECT line_icd9_dgns_cd FROM stg.carrier_line
    ) t WHERE dx IS NOT NULL;
    SET @n = @@ROWCOUNT;
    INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status)
    VALUES ('dw_dim_load', 'dim_diagnosis', @t0, SYSUTCDATETIME(), @n, (SELECT COUNT_BIG(*) FROM dw.dim_diagnosis),
            CASE WHEN @n = (SELECT COUNT_BIG(*) FROM dw.dim_diagnosis) THEN 'SUCCESS' ELSE 'FAILED' END);
END
GO

/* ---------- dim_procedure: ICD-9 procedure codes and HCPCS codes, kept apart by code_system ---------- */
IF OBJECT_ID(N'dw.dim_procedure', N'U') IS NULL
CREATE TABLE dw.dim_procedure (
    procedure_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_procedure PRIMARY KEY,
    code_system   VARCHAR(10)  NOT NULL,       -- 'ICD9-PCS' or 'HCPCS'
    code          VARCHAR(10)  NOT NULL,
    description   VARCHAR(300) NULL,
    CONSTRAINT UQ_dim_procedure UNIQUE (code_system, code),
    CONSTRAINT CK_dim_procedure_system CHECK (code_system IN ('ICD9-PCS','HCPCS'))
);
GO

DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME(), @n BIGINT;
IF NOT EXISTS (SELECT 1 FROM dw.dim_procedure)
BEGIN
    INSERT INTO dw.dim_procedure (code_system, code)
    SELECT code_system, code FROM (
        SELECT 'ICD9-PCS' AS code_system, v.px AS code FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.icd9_prcdr_cd_1), (c.icd9_prcdr_cd_2), (c.icd9_prcdr_cd_3), (c.icd9_prcdr_cd_4), (c.icd9_prcdr_cd_5), (c.icd9_prcdr_cd_6)) AS v(px)
        UNION
        SELECT 'ICD9-PCS' AS code_system, v.px AS code FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.icd9_prcdr_cd_1), (c.icd9_prcdr_cd_2), (c.icd9_prcdr_cd_3), (c.icd9_prcdr_cd_4), (c.icd9_prcdr_cd_5), (c.icd9_prcdr_cd_6)) AS v(px)
        UNION
        SELECT 'HCPCS' AS code_system, v.px AS code FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.hcpcs_cd_1), (c.hcpcs_cd_2), (c.hcpcs_cd_3), (c.hcpcs_cd_4), (c.hcpcs_cd_5), (c.hcpcs_cd_6), (c.hcpcs_cd_7), (c.hcpcs_cd_8), (c.hcpcs_cd_9), (c.hcpcs_cd_10), (c.hcpcs_cd_11), (c.hcpcs_cd_12), (c.hcpcs_cd_13), (c.hcpcs_cd_14), (c.hcpcs_cd_15), (c.hcpcs_cd_16), (c.hcpcs_cd_17), (c.hcpcs_cd_18), (c.hcpcs_cd_19), (c.hcpcs_cd_20), (c.hcpcs_cd_21), (c.hcpcs_cd_22), (c.hcpcs_cd_23), (c.hcpcs_cd_24), (c.hcpcs_cd_25), (c.hcpcs_cd_26), (c.hcpcs_cd_27), (c.hcpcs_cd_28), (c.hcpcs_cd_29), (c.hcpcs_cd_30), (c.hcpcs_cd_31), (c.hcpcs_cd_32), (c.hcpcs_cd_33), (c.hcpcs_cd_34), (c.hcpcs_cd_35), (c.hcpcs_cd_36), (c.hcpcs_cd_37), (c.hcpcs_cd_38), (c.hcpcs_cd_39), (c.hcpcs_cd_40), (c.hcpcs_cd_41), (c.hcpcs_cd_42), (c.hcpcs_cd_43), (c.hcpcs_cd_44), (c.hcpcs_cd_45)) AS v(px)
        UNION
        SELECT 'HCPCS' AS code_system, v.px AS code FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.hcpcs_cd_1), (c.hcpcs_cd_2), (c.hcpcs_cd_3), (c.hcpcs_cd_4), (c.hcpcs_cd_5), (c.hcpcs_cd_6), (c.hcpcs_cd_7), (c.hcpcs_cd_8), (c.hcpcs_cd_9), (c.hcpcs_cd_10), (c.hcpcs_cd_11), (c.hcpcs_cd_12), (c.hcpcs_cd_13), (c.hcpcs_cd_14), (c.hcpcs_cd_15), (c.hcpcs_cd_16), (c.hcpcs_cd_17), (c.hcpcs_cd_18), (c.hcpcs_cd_19), (c.hcpcs_cd_20), (c.hcpcs_cd_21), (c.hcpcs_cd_22), (c.hcpcs_cd_23), (c.hcpcs_cd_24), (c.hcpcs_cd_25), (c.hcpcs_cd_26), (c.hcpcs_cd_27), (c.hcpcs_cd_28), (c.hcpcs_cd_29), (c.hcpcs_cd_30), (c.hcpcs_cd_31), (c.hcpcs_cd_32), (c.hcpcs_cd_33), (c.hcpcs_cd_34), (c.hcpcs_cd_35), (c.hcpcs_cd_36), (c.hcpcs_cd_37), (c.hcpcs_cd_38), (c.hcpcs_cd_39), (c.hcpcs_cd_40), (c.hcpcs_cd_41), (c.hcpcs_cd_42), (c.hcpcs_cd_43), (c.hcpcs_cd_44), (c.hcpcs_cd_45)) AS v(px)
        UNION
        SELECT 'HCPCS', hcpcs_cd FROM stg.carrier_line
    ) t WHERE code IS NOT NULL;
    SET @n = @@ROWCOUNT;
    INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status)
    VALUES ('dw_dim_load', 'dim_procedure', @t0, SYSUTCDATETIME(), @n, (SELECT COUNT_BIG(*) FROM dw.dim_procedure),
            CASE WHEN @n = (SELECT COUNT_BIG(*) FROM dw.dim_procedure) THEN 'SUCCESS' ELSE 'FAILED' END);
END
GO

-- Coverage check: every code used on any staged claim must exist in the dimension (all values must be 0)
SELECT 'diagnosis from stg.inpatient_claim' AS check_name, COUNT(*) AS codes_missing_from_dim
FROM (SELECT DISTINCT v.dx FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.admtng_icd9_dgns_cd), (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8), (c.icd9_dgns_cd_9), (c.icd9_dgns_cd_10)) AS v(dx) WHERE v.dx IS NOT NULL) s
LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL
UNION ALL
SELECT 'diagnosis from stg.outpatient_claim' AS check_name, COUNT(*) AS codes_missing_from_dim
FROM (SELECT DISTINCT v.dx FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.admtng_icd9_dgns_cd), (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8), (c.icd9_dgns_cd_9), (c.icd9_dgns_cd_10)) AS v(dx) WHERE v.dx IS NOT NULL) s
LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL
UNION ALL
SELECT 'diagnosis from stg.carrier_claim' AS check_name, COUNT(*) AS codes_missing_from_dim
FROM (SELECT DISTINCT v.dx FROM stg.carrier_claim c CROSS APPLY (VALUES (c.icd9_dgns_cd_1), (c.icd9_dgns_cd_2), (c.icd9_dgns_cd_3), (c.icd9_dgns_cd_4), (c.icd9_dgns_cd_5), (c.icd9_dgns_cd_6), (c.icd9_dgns_cd_7), (c.icd9_dgns_cd_8)) AS v(dx) WHERE v.dx IS NOT NULL) s
LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL
UNION ALL
SELECT 'diagnosis from stg.carrier_line', COUNT(*)
FROM (SELECT DISTINCT line_icd9_dgns_cd AS dx FROM stg.carrier_line WHERE line_icd9_dgns_cd IS NOT NULL) s
LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL
UNION ALL
SELECT 'ICD9-PCS from stg.inpatient_claim (icd9_prcdr_cd_*)', COUNT(*)
FROM (SELECT DISTINCT v.px FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.icd9_prcdr_cd_1), (c.icd9_prcdr_cd_2), (c.icd9_prcdr_cd_3), (c.icd9_prcdr_cd_4), (c.icd9_prcdr_cd_5), (c.icd9_prcdr_cd_6)) AS v(px) WHERE v.px IS NOT NULL) s
LEFT JOIN dw.dim_procedure p ON p.code_system = 'ICD9-PCS' AND p.code = s.px WHERE p.procedure_key IS NULL
UNION ALL
SELECT 'ICD9-PCS from stg.outpatient_claim (icd9_prcdr_cd_*)', COUNT(*)
FROM (SELECT DISTINCT v.px FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.icd9_prcdr_cd_1), (c.icd9_prcdr_cd_2), (c.icd9_prcdr_cd_3), (c.icd9_prcdr_cd_4), (c.icd9_prcdr_cd_5), (c.icd9_prcdr_cd_6)) AS v(px) WHERE v.px IS NOT NULL) s
LEFT JOIN dw.dim_procedure p ON p.code_system = 'ICD9-PCS' AND p.code = s.px WHERE p.procedure_key IS NULL
UNION ALL
SELECT 'HCPCS from stg.inpatient_claim (hcpcs_cd_*)', COUNT(*)
FROM (SELECT DISTINCT v.px FROM stg.inpatient_claim c CROSS APPLY (VALUES (c.hcpcs_cd_1), (c.hcpcs_cd_2), (c.hcpcs_cd_3), (c.hcpcs_cd_4), (c.hcpcs_cd_5), (c.hcpcs_cd_6), (c.hcpcs_cd_7), (c.hcpcs_cd_8), (c.hcpcs_cd_9), (c.hcpcs_cd_10), (c.hcpcs_cd_11), (c.hcpcs_cd_12), (c.hcpcs_cd_13), (c.hcpcs_cd_14), (c.hcpcs_cd_15), (c.hcpcs_cd_16), (c.hcpcs_cd_17), (c.hcpcs_cd_18), (c.hcpcs_cd_19), (c.hcpcs_cd_20), (c.hcpcs_cd_21), (c.hcpcs_cd_22), (c.hcpcs_cd_23), (c.hcpcs_cd_24), (c.hcpcs_cd_25), (c.hcpcs_cd_26), (c.hcpcs_cd_27), (c.hcpcs_cd_28), (c.hcpcs_cd_29), (c.hcpcs_cd_30), (c.hcpcs_cd_31), (c.hcpcs_cd_32), (c.hcpcs_cd_33), (c.hcpcs_cd_34), (c.hcpcs_cd_35), (c.hcpcs_cd_36), (c.hcpcs_cd_37), (c.hcpcs_cd_38), (c.hcpcs_cd_39), (c.hcpcs_cd_40), (c.hcpcs_cd_41), (c.hcpcs_cd_42), (c.hcpcs_cd_43), (c.hcpcs_cd_44), (c.hcpcs_cd_45)) AS v(px) WHERE v.px IS NOT NULL) s
LEFT JOIN dw.dim_procedure p ON p.code_system = 'HCPCS' AND p.code = s.px WHERE p.procedure_key IS NULL
UNION ALL
SELECT 'HCPCS from stg.outpatient_claim (hcpcs_cd_*)', COUNT(*)
FROM (SELECT DISTINCT v.px FROM stg.outpatient_claim c CROSS APPLY (VALUES (c.hcpcs_cd_1), (c.hcpcs_cd_2), (c.hcpcs_cd_3), (c.hcpcs_cd_4), (c.hcpcs_cd_5), (c.hcpcs_cd_6), (c.hcpcs_cd_7), (c.hcpcs_cd_8), (c.hcpcs_cd_9), (c.hcpcs_cd_10), (c.hcpcs_cd_11), (c.hcpcs_cd_12), (c.hcpcs_cd_13), (c.hcpcs_cd_14), (c.hcpcs_cd_15), (c.hcpcs_cd_16), (c.hcpcs_cd_17), (c.hcpcs_cd_18), (c.hcpcs_cd_19), (c.hcpcs_cd_20), (c.hcpcs_cd_21), (c.hcpcs_cd_22), (c.hcpcs_cd_23), (c.hcpcs_cd_24), (c.hcpcs_cd_25), (c.hcpcs_cd_26), (c.hcpcs_cd_27), (c.hcpcs_cd_28), (c.hcpcs_cd_29), (c.hcpcs_cd_30), (c.hcpcs_cd_31), (c.hcpcs_cd_32), (c.hcpcs_cd_33), (c.hcpcs_cd_34), (c.hcpcs_cd_35), (c.hcpcs_cd_36), (c.hcpcs_cd_37), (c.hcpcs_cd_38), (c.hcpcs_cd_39), (c.hcpcs_cd_40), (c.hcpcs_cd_41), (c.hcpcs_cd_42), (c.hcpcs_cd_43), (c.hcpcs_cd_44), (c.hcpcs_cd_45)) AS v(px) WHERE v.px IS NOT NULL) s
LEFT JOIN dw.dim_procedure p ON p.code_system = 'HCPCS' AND p.code = s.px WHERE p.procedure_key IS NULL
UNION ALL
SELECT 'HCPCS from stg.carrier_line', COUNT(*)
FROM (SELECT DISTINCT hcpcs_cd AS px FROM stg.carrier_line WHERE hcpcs_cd IS NOT NULL) s
LEFT JOIN dw.dim_procedure p ON p.code_system = 'HCPCS' AND p.code = s.px WHERE p.procedure_key IS NULL;


SELECT COUNT(*) AS diagnosis_codes FROM dw.dim_diagnosis;
SELECT code_system, COUNT(*) AS codes FROM dw.dim_procedure GROUP BY code_system;

-- Common ICD-9 codes: hypertension, diabetes, atrial fibrillation, heart failure
SELECT icd9_code FROM dw.dim_diagnosis WHERE icd9_code IN ('4019','25000','42731','4280');

SELECT TOP 2 * FROM audit.load_log ORDER BY load_id DESC;