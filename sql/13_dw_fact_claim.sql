USE PayerPulse;

-- 1) Orphan segment-2 claims (expect 278)
SELECT COUNT(*) AS claims_without_segment1, SUM(pay) AS their_payments
FROM (SELECT clm_id, SUM(clm_pmt_amt) AS pay FROM stg.outpatient_claim GROUP BY clm_id
      HAVING MAX(CASE WHEN segment = 1 THEN 1 ELSE 0 END) = 0) x;

-- 2) All dates must fall inside dim_date (2007-01-01 to 2011-12-31), or the date keys will fail
SELECT 'inpatient' AS src, MIN(clm_from_dt) AS min_from, MAX(clm_thru_dt) AS max_thru,
       MIN(clm_admsn_dt) AS min_admit, MAX(nch_bene_dschrg_dt) AS max_discharge
FROM stg.inpatient_claim
UNION ALL SELECT 'outpatient', MIN(clm_from_dt), MAX(clm_thru_dt), NULL, NULL FROM stg.outpatient_claim
UNION ALL SELECT 'carrier', MIN(from_date), MAX(thru_date), NULL, NULL FROM stg.carrier_claim;

USE PayerPulse;
GO

IF OBJECT_ID(N'dw.fact_claim', N'U') IS NOT NULL DROP TABLE dw.fact_claim;
GO
-- Created WITHOUT keys so the big load is minimally logged; constraints are added after the load.
CREATE TABLE dw.fact_claim (
    claim_key              BIGINT IDENTITY(1,1) NOT NULL,
    claim_type             VARCHAR(10)   NOT NULL,   -- INPATIENT / OUTPATIENT / CARRIER
    claim_id               VARCHAR(20)   NOT NULL,
    beneficiary_key        INT           NOT NULL,
    from_date_key          INT           NULL,
    thru_date_key          INT           NULL,
    admit_date_key         INT           NULL,       -- inpatient only
    discharge_date_key     INT           NULL,       -- inpatient only
    facility_key           INT           NULL,       -- inpatient/outpatient institution
    attending_npi_key      INT           NULL,
    operating_npi_key      INT           NULL,
    drg_key                INT           NULL,       -- inpatient only
    admitting_dx_key       INT           NULL,
    principal_dx_key       INT           NULL,       -- first diagnosis on the claim
    utilization_days       SMALLINT      NULL,       -- as reported (inpatient)
    los_days               SMALLINT      NULL,       -- calendar days, discharge minus admit (inpatient)
    medicare_paid_amt      DECIMAL(14,2) NULL,       -- summed across all segments / lines
    primary_payer_paid_amt DECIMAL(14,2) NULL,
    bene_deductible_amt    DECIMAL(14,2) NULL,
    bene_coinsurance_amt   DECIMAL(14,2) NULL,
    allowed_amt            DECIMAL(14,2) NULL,       -- carrier only
    segment_count          TINYINT       NULL,       -- inpatient/outpatient
    line_count             SMALLINT      NULL,       -- carrier
    is_adjustment          BIT           NOT NULL,   -- any segment with a negative payment
    is_orphan_segment      BIT           NOT NULL    -- claim exists only as a segment-2 record (no dates)
);
GO

DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME();

/* ---------- inpatient ---------- */
;WITH hdr AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY segment) AS rn
    FROM stg.inpatient_claim
), seg AS (
    SELECT clm_id, COUNT(*) AS segment_count,
           SUM(clm_pmt_amt) AS medicare_paid, SUM(nch_prmry_pyr_clm_pd_amt) AS primary_paid,
           SUM(nch_bene_ip_ddctbl_amt) AS deductible, SUM(nch_bene_pta_coinsrnc_lblty_am) AS coinsurance,
           MAX(CAST(is_adjustment AS int)) AS is_adj
    FROM stg.inpatient_claim GROUP BY clm_id
)
INSERT INTO dw.fact_claim WITH (TABLOCK)
    (claim_type, claim_id, beneficiary_key, from_date_key, thru_date_key, admit_date_key, discharge_date_key,
     facility_key, attending_npi_key, operating_npi_key, drg_key, admitting_dx_key, principal_dx_key,
     utilization_days, los_days, medicare_paid_amt, primary_payer_paid_amt, bene_deductible_amt,
     bene_coinsurance_amt, allowed_amt, segment_count, line_count, is_adjustment, is_orphan_segment)
SELECT 'INPATIENT', h.clm_id, b.beneficiary_key,
       CONVERT(int, CONVERT(char(8), h.clm_from_dt, 112)), CONVERT(int, CONVERT(char(8), h.clm_thru_dt, 112)),
       CONVERT(int, CONVERT(char(8), h.clm_admsn_dt, 112)), CONVERT(int, CONVERT(char(8), h.nch_bene_dschrg_dt, 112)),
       fac.provider_key, att.provider_key, opr.provider_key, drg.drg_key, adx.diagnosis_key, pdx.diagnosis_key,
       h.clm_utlztn_day_cnt, DATEDIFF(day, h.clm_admsn_dt, h.nch_bene_dschrg_dt),
       s.medicare_paid, s.primary_paid, s.deductible, s.coinsurance, NULL, s.segment_count, NULL,
       s.is_adj, CASE WHEN h.segment <> 1 THEN 1 ELSE 0 END
FROM hdr h
JOIN seg s ON s.clm_id = h.clm_id
JOIN dw.dim_beneficiary b ON b.desynpuf_id = h.desynpuf_id
LEFT JOIN dw.dim_provider fac ON fac.provider_id_type = 'FACILITY' AND fac.provider_id = h.prvdr_num
LEFT JOIN dw.dim_provider att ON att.provider_id_type = 'NPI' AND att.provider_id = h.at_physn_npi
LEFT JOIN dw.dim_provider opr ON opr.provider_id_type = 'NPI' AND opr.provider_id = h.op_physn_npi
LEFT JOIN dw.dim_drg drg ON drg.drg_code = h.clm_drg_cd
LEFT JOIN dw.dim_diagnosis adx ON adx.icd9_code = h.admtng_icd9_dgns_cd
LEFT JOIN dw.dim_diagnosis pdx ON pdx.icd9_code = h.icd9_dgns_cd_1
WHERE h.rn = 1;

/* ---------- outpatient ---------- */
;WITH hdr AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY segment) AS rn
    FROM stg.outpatient_claim
), seg AS (
    SELECT clm_id, COUNT(*) AS segment_count,
           SUM(clm_pmt_amt) AS medicare_paid, SUM(nch_prmry_pyr_clm_pd_amt) AS primary_paid,
           SUM(nch_bene_ptb_ddctbl_amt) AS deductible, SUM(nch_bene_ptb_coinsrnc_amt) AS coinsurance,
           MAX(CAST(is_adjustment AS int)) AS is_adj
    FROM stg.outpatient_claim GROUP BY clm_id
)
INSERT INTO dw.fact_claim WITH (TABLOCK)
    (claim_type, claim_id, beneficiary_key, from_date_key, thru_date_key, admit_date_key, discharge_date_key,
     facility_key, attending_npi_key, operating_npi_key, drg_key, admitting_dx_key, principal_dx_key,
     utilization_days, los_days, medicare_paid_amt, primary_payer_paid_amt, bene_deductible_amt,
     bene_coinsurance_amt, allowed_amt, segment_count, line_count, is_adjustment, is_orphan_segment)
SELECT 'OUTPATIENT', h.clm_id, b.beneficiary_key,
       CONVERT(int, CONVERT(char(8), h.clm_from_dt, 112)), CONVERT(int, CONVERT(char(8), h.clm_thru_dt, 112)),
       NULL, NULL,
       fac.provider_key, att.provider_key, opr.provider_key, NULL, adx.diagnosis_key, pdx.diagnosis_key,
       NULL, NULL,
       s.medicare_paid, s.primary_paid, s.deductible, s.coinsurance, NULL, s.segment_count, NULL,
       s.is_adj, CASE WHEN h.segment <> 1 THEN 1 ELSE 0 END
FROM hdr h
JOIN seg s ON s.clm_id = h.clm_id
JOIN dw.dim_beneficiary b ON b.desynpuf_id = h.desynpuf_id
LEFT JOIN dw.dim_provider fac ON fac.provider_id_type = 'FACILITY' AND fac.provider_id = h.prvdr_num
LEFT JOIN dw.dim_provider att ON att.provider_id_type = 'NPI' AND att.provider_id = h.at_physn_npi
LEFT JOIN dw.dim_provider opr ON opr.provider_id_type = 'NPI' AND opr.provider_id = h.op_physn_npi
LEFT JOIN dw.dim_diagnosis adx ON adx.icd9_code = h.admtng_icd9_dgns_cd
LEFT JOIN dw.dim_diagnosis pdx ON pdx.icd9_code = h.icd9_dgns_cd_1
WHERE h.rn = 1;

/* ---------- carrier (claim totals come from the service lines) ---------- */
;WITH ln AS (
    SELECT clm_id, COUNT(*) AS line_count,
           SUM(line_nch_pmt_amt) AS medicare_paid, SUM(line_bene_prmry_pyr_pd_amt) AS primary_paid,
           SUM(line_bene_ptb_ddctbl_amt) AS deductible, SUM(line_coinsrnc_amt) AS coinsurance,
           SUM(line_alowd_chrg_amt) AS allowed,
           MAX(CASE WHEN line_nch_pmt_amt < 0 THEN 1 ELSE 0 END) AS has_neg
    FROM stg.carrier_line GROUP BY clm_id
)
INSERT INTO dw.fact_claim WITH (TABLOCK)
    (claim_type, claim_id, beneficiary_key, from_date_key, thru_date_key, admit_date_key, discharge_date_key,
     facility_key, attending_npi_key, operating_npi_key, drg_key, admitting_dx_key, principal_dx_key,
     utilization_days, los_days, medicare_paid_amt, primary_payer_paid_amt, bene_deductible_amt,
     bene_coinsurance_amt, allowed_amt, segment_count, line_count, is_adjustment, is_orphan_segment)
SELECT 'CARRIER', c.clm_id, b.beneficiary_key,
       CONVERT(int, CONVERT(char(8), c.from_date, 112)), CONVERT(int, CONVERT(char(8), c.thru_date, 112)),
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, pdx.diagnosis_key,
       NULL, NULL,
       l.medicare_paid, l.primary_paid, l.deductible, l.coinsurance, l.allowed, NULL, l.line_count,
       ISNULL(l.has_neg, 0), 0
FROM stg.carrier_claim c
LEFT JOIN ln l ON l.clm_id = c.clm_id
JOIN dw.dim_beneficiary b ON b.desynpuf_id = c.desynpuf_id
LEFT JOIN dw.dim_diagnosis pdx ON pdx.icd9_code = c.icd9_dgns_cd_1;

/* ---------- audit: claim count and Medicare-paid total must reconcile to staging ---------- */
DECLARE @exp BIGINT =
      (SELECT COUNT(DISTINCT clm_id) FROM stg.inpatient_claim)
    + (SELECT COUNT(DISTINCT clm_id) FROM stg.outpatient_claim)
    + (SELECT COUNT_BIG(*) FROM stg.carrier_claim);
DECLARE @got BIGINT = (SELECT COUNT_BIG(*) FROM dw.fact_claim);
DECLARE @stg_pmt DECIMAL(18,2) =
      (SELECT SUM(clm_pmt_amt) FROM stg.inpatient_claim)
    + (SELECT SUM(clm_pmt_amt) FROM stg.outpatient_claim)
    + (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line);
DECLARE @dw_pmt DECIMAL(18,2) = (SELECT SUM(medicare_paid_amt) FROM dw.fact_claim);

INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status, error_message)
VALUES ('dw_fact_load', 'dw.fact_claim', @t0, SYSUTCDATETIME(), @exp, @got,
        CASE WHEN @exp = @got AND @stg_pmt = @dw_pmt THEN 'SUCCESS' ELSE 'FAILED' END,
        CASE WHEN @exp = @got AND @stg_pmt = @dw_pmt THEN NULL
             ELSE N'Reconciliation failed: claims expected ' + CAST(@exp AS NVARCHAR(20)) + N' got ' + CAST(@got AS NVARCHAR(20))
                  + N'; Medicare paid staging ' + CAST(@stg_pmt AS NVARCHAR(30)) + N' vs warehouse ' + CAST(@dw_pmt AS NVARCHAR(30)) END);
