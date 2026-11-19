-- Should return no rows: each member appears once per year
SELECT file_year, desynpuf_id, COUNT(*) AS n
FROM raw.beneficiary_summary
GROUP BY file_year, desynpuf_id HAVING COUNT(*) > 1;

-- Expect sex 1/2, race 1/2/3/5, esrd 0/Y only
SELECT bene_sex_ident_cd, bene_race_cd, bene_esrd_ind, COUNT(*) AS n
FROM raw.beneficiary_summary
GROUP BY bene_sex_ident_cd, bene_race_cd, bene_esrd_ind
ORDER BY 1, 2, 3;

USE PayerPulse;
GO
IF OBJECT_ID(N'stg.beneficiary', N'U') IS NOT NULL DROP TABLE stg.beneficiary;
GO
CREATE TABLE stg.beneficiary (
    desynpuf_id     VARCHAR(16) NOT NULL,
    coverage_year   SMALLINT    NOT NULL,
    birth_date      DATE        NULL,
    death_date      DATE        NULL,
    sex_code        CHAR(1)     NULL,   -- 1 male, 2 female
    race_code       CHAR(1)     NULL,   -- 1 white, 2 black, 3 other, 5 hispanic
    esrd_flag       BIT         NULL,
    state_code      VARCHAR(2)  NULL,
    county_code     VARCHAR(3)  NULL,
    part_a_months   TINYINT     NULL,
    part_b_months   TINYINT     NULL,
    hmo_months      TINYINT     NULL,
    part_d_months   TINYINT     NULL,
    has_alzheimers  BIT NULL, has_chf BIT NULL, has_ckd BIT NULL, has_cancer BIT NULL,
    has_copd        BIT NULL, has_depression BIT NULL, has_diabetes BIT NULL, has_ihd BIT NULL,
    has_osteoporosis BIT NULL, has_ra_oa BIT NULL, has_stroke_tia BIT NULL,
    medicare_reimb_ip  DECIMAL(12,2) NULL, bene_resp_ip  DECIMAL(12,2) NULL, primary_payer_pmt_ip  DECIMAL(12,2) NULL,
    medicare_reimb_op  DECIMAL(12,2) NULL, bene_resp_op  DECIMAL(12,2) NULL, primary_payer_pmt_op  DECIMAL(12,2) NULL,
    medicare_reimb_car DECIMAL(12,2) NULL, bene_resp_car DECIMAL(12,2) NULL, primary_payer_pmt_car DECIMAL(12,2) NULL,
    CONSTRAINT PK_stg_beneficiary PRIMARY KEY (desynpuf_id, coverage_year)
);
GO

DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;
SELECT @raw_rows = COUNT_BIG(*) FROM raw.beneficiary_summary;

INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)
VALUES ('stg_load', 'raw.beneficiary_summary -> stg.beneficiary', @raw_rows);
SET @load_id = SCOPE_IDENTITY();

INSERT INTO stg.beneficiary
SELECT
    desynpuf_id, file_year,
    TRY_CONVERT(date, bene_birth_dt, 112), TRY_CONVERT(date, bene_death_dt, 112),
    bene_sex_ident_cd, bene_race_cd,
    CASE bene_esrd_ind WHEN 'Y' THEN 1 WHEN '0' THEN 0 END,
    sp_state_code, bene_county_cd,
    TRY_CONVERT(tinyint, bene_hi_cvrage_tot_mons), TRY_CONVERT(tinyint, bene_smi_cvrage_tot_mons),
    TRY_CONVERT(tinyint, bene_hmo_cvrage_tot_mons), TRY_CONVERT(tinyint, plan_cvrg_mos_num),
    CASE sp_alzhdmta WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_chf      WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_chrnkidn WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_cncr     WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_copd     WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_depressn WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_diabetes WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_ischmcht WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_osteoprs WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_ra_oa    WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    CASE sp_strketia WHEN '1' THEN 1 WHEN '2' THEN 0 END,
    TRY_CONVERT(decimal(12,2), medreimb_ip),  TRY_CONVERT(decimal(12,2), benres_ip),  TRY_CONVERT(decimal(12,2), pppymt_ip),
    TRY_CONVERT(decimal(12,2), medreimb_op),  TRY_CONVERT(decimal(12,2), benres_op),  TRY_CONVERT(decimal(12,2), pppymt_op),
    TRY_CONVERT(decimal(12,2), medreimb_car), TRY_CONVERT(decimal(12,2), benres_car), TRY_CONVERT(decimal(12,2), pppymt_car)
FROM raw.beneficiary_summary;
SET @loaded = @@ROWCOUNT;

UPDATE audit.load_log
SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,
    status = CASE WHEN @loaded = @raw_rows THEN 'SUCCESS' ELSE 'FAILED' END
WHERE load_id = @load_id;
GO

SELECT coverage_year, COUNT(*) AS n FROM stg.beneficiary GROUP BY coverage_year ORDER BY coverage_year;  -- 116,352 / 114,538 / 112,754

SELECT COUNT(*) AS total,
       SUM(CASE WHEN birth_date IS NULL THEN 1 ELSE 0 END) AS birth_null,       -- expect 0
       SUM(CASE WHEN death_date IS NULL THEN 1 ELSE 0 END) AS death_null,       -- expect 338,183
       SUM(CAST(has_chf AS int)) AS chf_yes,                                    -- expect 101,752
       SUM(CASE WHEN esrd_flag IS NULL THEN 1 ELSE 0 END) AS esrd_null         -- expect 0
FROM stg.beneficiary;

SELECT TOP 1 * FROM audit.load_log ORDER BY load_id DESC;