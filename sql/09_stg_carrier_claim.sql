USE PayerPulse;
GO

IF OBJECT_ID(N'stg.carrier_claim', N'U') IS NOT NULL DROP TABLE stg.carrier_claim;
GO
CREATE TABLE stg.carrier_claim (
    clm_id      VARCHAR(20) NOT NULL,
    desynpuf_id VARCHAR(16) NOT NULL,
    from_date   DATE NULL,
    thru_date   DATE NULL,
    icd9_dgns_cd_1 VARCHAR(10) NULL,
    icd9_dgns_cd_2 VARCHAR(10) NULL,
    icd9_dgns_cd_3 VARCHAR(10) NULL,
    icd9_dgns_cd_4 VARCHAR(10) NULL,
    icd9_dgns_cd_5 VARCHAR(10) NULL,
    icd9_dgns_cd_6 VARCHAR(10) NULL,
    icd9_dgns_cd_7 VARCHAR(10) NULL,
    icd9_dgns_cd_8 VARCHAR(10) NULL,
    CONSTRAINT PK_stg_carrier_claim PRIMARY KEY (clm_id)
);
GO
DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;
SELECT @raw_rows = COUNT_BIG(*) FROM raw.carrier_claims;
INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)
VALUES ('stg_load', 'raw.carrier_claims -> stg.carrier_claim', @raw_rows);
SET @load_id = SCOPE_IDENTITY();

INSERT INTO stg.carrier_claim (clm_id, desynpuf_id, from_date, thru_date, icd9_dgns_cd_1, icd9_dgns_cd_2, icd9_dgns_cd_3, icd9_dgns_cd_4, icd9_dgns_cd_5, icd9_dgns_cd_6, icd9_dgns_cd_7, icd9_dgns_cd_8)
SELECT clm_id, desynpuf_id, TRY_CONVERT(date, clm_from_dt, 112), TRY_CONVERT(date, clm_thru_dt, 112), icd9_dgns_cd_1, icd9_dgns_cd_2, icd9_dgns_cd_3, icd9_dgns_cd_4, icd9_dgns_cd_5, icd9_dgns_cd_6, icd9_dgns_cd_7, icd9_dgns_cd_8
FROM raw.carrier_claims;
SET @loaded = @@ROWCOUNT;

UPDATE audit.load_log
SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,
    status = CASE WHEN @loaded = @raw_rows THEN 'SUCCESS' ELSE 'FAILED' END
WHERE load_id = @load_id;
GO

-- Conversion check: raw_non_null must equal stg_non_null on every row
SELECT 'claim rows' AS col, (SELECT COUNT_BIG(*) FROM raw.carrier_claims) AS raw_non_null, (SELECT COUNT_BIG(*) FROM stg.carrier_claim) AS stg_non_null
UNION ALL SELECT 'clm_from_dt', (SELECT COUNT_BIG(clm_from_dt) FROM raw.carrier_claims), (SELECT COUNT_BIG(from_date) FROM stg.carrier_claim)
UNION ALL SELECT 'clm_thru_dt', (SELECT COUNT_BIG(clm_thru_dt) FROM raw.carrier_claims), (SELECT COUNT_BIG(thru_date) FROM stg.carrier_claim);
