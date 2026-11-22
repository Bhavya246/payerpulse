EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 4096; RECONFIGURE;

USE PayerPulse;
GO

/* ===================== fact_member_year: one row per member per coverage year ===================== */
IF OBJECT_ID(N'dw.fact_member_year', N'U') IS NOT NULL DROP TABLE dw.fact_member_year;
GO
CREATE TABLE dw.fact_member_year (
    beneficiary_key      INT      NOT NULL,
    coverage_year        SMALLINT NOT NULL,
    state_code           VARCHAR(2) NULL,
    county_code          VARCHAR(3) NULL,
    esrd_flag            BIT      NULL,
    part_a_months        TINYINT  NULL,
    part_b_months        TINYINT  NULL,
    hmo_months           TINYINT  NULL,
    part_d_months        TINYINT  NULL,
    has_alzheimers BIT NULL, has_chf BIT NULL, has_ckd BIT NULL, has_cancer BIT NULL, has_copd BIT NULL,
    has_depression BIT NULL, has_diabetes BIT NULL, has_ihd BIT NULL, has_osteoporosis BIT NULL,
    has_ra_oa BIT NULL, has_stroke_tia BIT NULL,
    medicare_reimb_ip  DECIMAL(12,2) NULL, bene_resp_ip  DECIMAL(12,2) NULL, primary_payer_pmt_ip  DECIMAL(12,2) NULL,
    medicare_reimb_op  DECIMAL(12,2) NULL, bene_resp_op  DECIMAL(12,2) NULL, primary_payer_pmt_op  DECIMAL(12,2) NULL,
    medicare_reimb_car DECIMAL(12,2) NULL, bene_resp_car DECIMAL(12,2) NULL, primary_payer_pmt_car DECIMAL(12,2) NULL
);
GO
DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dw.fact_member_year WITH (TABLOCK)
SELECT b.beneficiary_key, s.coverage_year, s.state_code, s.county_code, s.esrd_flag,
       s.part_a_months, s.part_b_months, s.hmo_months, s.part_d_months,
       s.has_alzheimers, s.has_chf, s.has_ckd, s.has_cancer, s.has_copd,
       s.has_depression, s.has_diabetes, s.has_ihd, s.has_osteoporosis, s.has_ra_oa, s.has_stroke_tia,
       s.medicare_reimb_ip, s.bene_resp_ip, s.primary_payer_pmt_ip,
       s.medicare_reimb_op, s.bene_resp_op, s.primary_payer_pmt_op,
       s.medicare_reimb_car, s.bene_resp_car, s.primary_payer_pmt_car
FROM stg.beneficiary s
JOIN dw.dim_beneficiary b ON b.desynpuf_id = s.desynpuf_id;

DECLARE @exp BIGINT = (SELECT COUNT_BIG(*) FROM stg.beneficiary);
DECLARE @got BIGINT = (SELECT COUNT_BIG(*) FROM dw.fact_member_year);
DECLARE @stg_amt DECIMAL(18,2) = (SELECT SUM(ISNULL(medicare_reimb_ip,0) + ISNULL(medicare_reimb_op,0) + ISNULL(medicare_reimb_car,0)) FROM stg.beneficiary);
DECLARE @dw_amt  DECIMAL(18,2) = (SELECT SUM(ISNULL(medicare_reimb_ip,0) + ISNULL(medicare_reimb_op,0) + ISNULL(medicare_reimb_car,0)) FROM dw.fact_member_year);

INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status, error_message)
VALUES ('dw_fact_load', 'dw.fact_member_year', @t0, SYSUTCDATETIME(), @exp, @got,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN 'SUCCESS' ELSE 'FAILED' END,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN NULL
             ELSE N'Reconciliation failed: rows ' + CAST(@exp AS NVARCHAR(20)) + N' vs ' + CAST(@got AS NVARCHAR(20))
                  + N'; annual Medicare reimbursement ' + CAST(@stg_amt AS NVARCHAR(30)) + N' vs ' + CAST(@dw_amt AS NVARCHAR(30)) END);
GO
ALTER TABLE dw.fact_member_year ADD CONSTRAINT PK_fact_member_year PRIMARY KEY CLUSTERED (beneficiary_key, coverage_year);
ALTER TABLE dw.fact_member_year ADD CONSTRAINT FK_fmy_beneficiary FOREIGN KEY (beneficiary_key) REFERENCES dw.dim_beneficiary(beneficiary_key);
GO

/* ===================== fact_rx_event: Part D prescription fills ===================== */
IF OBJECT_ID(N'dw.fact_rx_event', N'U') IS NOT NULL DROP TABLE dw.fact_rx_event;
GO
CREATE TABLE dw.fact_rx_event (
    rx_event_key       BIGINT IDENTITY(1,1) NOT NULL,
    pde_id             VARCHAR(20)   NOT NULL,
    beneficiary_key    INT           NOT NULL,
    service_date_key   INT           NULL,
    ndc_key            INT           NULL,
    quantity_dispensed DECIMAL(12,3) NULL,
    days_supply        SMALLINT      NULL,
    patient_pay_amt    DECIMAL(12,2) NULL,
    total_rx_cost_amt  DECIMAL(12,2) NULL,
    ndc_is_other       BIT           NOT NULL
);
GO
DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dw.fact_rx_event WITH (TABLOCK)
    (pde_id, beneficiary_key, service_date_key, ndc_key, quantity_dispensed, days_supply,
     patient_pay_amt, total_rx_cost_amt, ndc_is_other)
SELECT e.pde_id, b.beneficiary_key, CONVERT(int, CONVERT(char(8), e.service_date, 112)), n.ndc_key,
       e.quantity_dispensed, e.days_supply, e.patient_pay_amt, e.total_rx_cost_amt, e.ndc_is_other
FROM stg.pde_event e
JOIN dw.dim_beneficiary b ON b.desynpuf_id = e.desynpuf_id
LEFT JOIN dw.dim_ndc n ON n.ndc_code = e.ndc_code
OPTION (MAXDOP 2);

DECLARE @exp BIGINT = (SELECT COUNT_BIG(*) FROM stg.pde_event);
DECLARE @got BIGINT = (SELECT COUNT_BIG(*) FROM dw.fact_rx_event);
DECLARE @stg_amt DECIMAL(18,2) = (SELECT SUM(ISNULL(total_rx_cost_amt,0) + ISNULL(patient_pay_amt,0)) FROM stg.pde_event);
DECLARE @dw_amt  DECIMAL(18,2) = (SELECT SUM(ISNULL(total_rx_cost_amt,0) + ISNULL(patient_pay_amt,0)) FROM dw.fact_rx_event);

INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status, error_message)
VALUES ('dw_fact_load', 'dw.fact_rx_event', @t0, SYSUTCDATETIME(), @exp, @got,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN 'SUCCESS' ELSE 'FAILED' END,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN NULL
             ELSE N'Reconciliation failed: rows ' + CAST(@exp AS NVARCHAR(20)) + N' vs ' + CAST(@got AS NVARCHAR(20))
                  + N'; cost+patient pay ' + CAST(@stg_amt AS NVARCHAR(30)) + N' vs ' + CAST(@dw_amt AS NVARCHAR(30)) END);
GO
ALTER TABLE dw.fact_rx_event ADD CONSTRAINT PK_fact_rx_event PRIMARY KEY CLUSTERED (rx_event_key);
ALTER TABLE dw.fact_rx_event ADD CONSTRAINT UQ_fact_rx_pde UNIQUE (pde_id);
ALTER TABLE dw.fact_rx_event ADD CONSTRAINT FK_rx_beneficiary FOREIGN KEY (beneficiary_key)  REFERENCES dw.dim_beneficiary(beneficiary_key);
ALTER TABLE dw.fact_rx_event ADD CONSTRAINT FK_rx_date        FOREIGN KEY (service_date_key) REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_rx_event ADD CONSTRAINT FK_rx_ndc         FOREIGN KEY (ndc_key)          REFERENCES dw.dim_ndc(ndc_key);
GO

/* ===================== fact_claim_line: carrier service lines ===================== */
IF OBJECT_ID(N'dw.fact_claim_line', N'U') IS NOT NULL DROP TABLE dw.fact_claim_line;
GO
CREATE TABLE dw.fact_claim_line (
    claim_key              BIGINT        NOT NULL,
    line_number            TINYINT       NOT NULL,
    performing_npi_key     INT           NULL,
    procedure_key          INT           NULL,       -- HCPCS
    line_dx_key            INT           NULL,
    line_payment_amt       DECIMAL(12,2) NULL,
    line_allowed_amt       DECIMAL(12,2) NULL,
    line_deductible_amt    DECIMAL(12,2) NULL,
    line_primary_payer_amt DECIMAL(12,2) NULL,
    line_coinsurance_amt   DECIMAL(12,2) NULL,
    line_processing_ind    VARCHAR(5)    NULL,
    is_unidentified_line   BIT           NOT NULL    -- kept, but has neither an NPI nor an HCPCS code
);
GO
DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dw.fact_claim_line WITH (TABLOCK)
    (claim_key, line_number, performing_npi_key, procedure_key, line_dx_key, line_payment_amt, line_allowed_amt,
     line_deductible_amt, line_primary_payer_amt, line_coinsurance_amt, line_processing_ind, is_unidentified_line)
SELECT fc.claim_key, l.line_number, npi.provider_key, px.procedure_key, dx.diagnosis_key,
       l.line_nch_pmt_amt, l.line_alowd_chrg_amt, l.line_bene_ptb_ddctbl_amt, l.line_bene_prmry_pyr_pd_amt,
       l.line_coinsrnc_amt, l.line_prcsg_ind_cd,
       CASE WHEN l.hcpcs_cd IS NULL AND l.prf_physn_npi IS NULL THEN 1 ELSE 0 END
FROM stg.carrier_line l
JOIN dw.fact_claim fc ON fc.claim_type = 'CARRIER' AND fc.claim_id = l.clm_id
LEFT JOIN dw.dim_provider npi ON npi.provider_id_type = 'NPI' AND npi.provider_id = l.prf_physn_npi
LEFT JOIN dw.dim_procedure px ON px.code_system = 'HCPCS' AND px.code = l.hcpcs_cd
LEFT JOIN dw.dim_diagnosis dx ON dx.icd9_code = l.line_icd9_dgns_cd
OPTION (MAXDOP 2);

DECLARE @exp BIGINT = (SELECT COUNT_BIG(*) FROM stg.carrier_line);
DECLARE @got BIGINT = (SELECT COUNT_BIG(*) FROM dw.fact_claim_line);
DECLARE @stg_amt DECIMAL(18,2) = (SELECT SUM(ISNULL(line_nch_pmt_amt,0) + ISNULL(line_alowd_chrg_amt,0)) FROM stg.carrier_line);
DECLARE @dw_amt  DECIMAL(18,2) = (SELECT SUM(ISNULL(line_payment_amt,0) + ISNULL(line_allowed_amt,0)) FROM dw.fact_claim_line);

INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status, error_message)
VALUES ('dw_fact_load', 'dw.fact_claim_line', @t0, SYSUTCDATETIME(), @exp, @got,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN 'SUCCESS' ELSE 'FAILED' END,
        CASE WHEN @exp = @got AND @stg_amt = @dw_amt THEN NULL
             ELSE N'Reconciliation failed: lines ' + CAST(@exp AS NVARCHAR(20)) + N' vs ' + CAST(@got AS NVARCHAR(20))
                  + N'; payment+allowed ' + CAST(@stg_amt AS NVARCHAR(30)) + N' vs ' + CAST(@dw_amt AS NVARCHAR(30)) END);
GO
ALTER TABLE dw.fact_claim_line ADD CONSTRAINT PK_fact_claim_line PRIMARY KEY CLUSTERED (claim_key, line_number);
ALTER TABLE dw.fact_claim_line ADD CONSTRAINT FK_fcl_claim FOREIGN KEY (claim_key)          REFERENCES dw.fact_claim(claim_key);
ALTER TABLE dw.fact_claim_line ADD CONSTRAINT FK_fcl_npi   FOREIGN KEY (performing_npi_key) REFERENCES dw.dim_provider(provider_key);
ALTER TABLE dw.fact_claim_line ADD CONSTRAINT FK_fcl_proc  FOREIGN KEY (procedure_key)      REFERENCES dw.dim_procedure(procedure_key);
ALTER TABLE dw.fact_claim_line ADD CONSTRAINT FK_fcl_dx    FOREIGN KEY (line_dx_key)        REFERENCES dw.dim_diagnosis(diagnosis_key);
GO

-- 1) Row counts (expect 343,644 / 5,552,421 / 9,389,003)
SELECT 'fact_member_year' AS tbl, COUNT_BIG(*) AS in_fact, (SELECT COUNT_BIG(*) FROM stg.beneficiary) AS expected FROM dw.fact_member_year
UNION ALL SELECT 'fact_rx_event', COUNT_BIG(*), (SELECT COUNT_BIG(*) FROM stg.pde_event) FROM dw.fact_rx_event
UNION ALL SELECT 'fact_claim_line', COUNT_BIG(*), (SELECT COUNT_BIG(*) FROM stg.carrier_line) FROM dw.fact_claim_line;

-- 2) Dollars must match exactly
SELECT 'carrier line payments' AS check_name, (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line) AS staging,
       (SELECT SUM(line_payment_amt) FROM dw.fact_claim_line) AS warehouse
UNION ALL SELECT 'lines roll up to claim totals', (SELECT SUM(medicare_paid_amt) FROM dw.fact_claim WHERE claim_type = 'CARRIER'),
       (SELECT SUM(line_payment_amt) FROM dw.fact_claim_line)
UNION ALL SELECT 'rx total cost', (SELECT SUM(total_rx_cost_amt) FROM stg.pde_event), (SELECT SUM(total_rx_cost_amt) FROM dw.fact_rx_event)
UNION ALL SELECT 'member-year Medicare reimbursement',
       (SELECT SUM(ISNULL(medicare_reimb_ip,0) + ISNULL(medicare_reimb_op,0) + ISNULL(medicare_reimb_car,0)) FROM stg.beneficiary),
       (SELECT SUM(ISNULL(medicare_reimb_ip,0) + ISNULL(medicare_reimb_op,0) + ISNULL(medicare_reimb_car,0)) FROM dw.fact_member_year);

-- 3) Unidentified lines (expect 1,106 lines carrying 34,140.00, as found during staging)
SELECT COUNT(*) AS unidentified_lines, SUM(line_payment_amt) AS their_payments FROM dw.fact_claim_line WHERE is_unidentified_line = 1;

-- 4) Every dw fact has its keys (expect fact_claim 11, fact_claim_line 4, fact_member_year 1, fact_rx_event 3)
SELECT OBJECT_NAME(parent_object_id) AS dw_table, COUNT(*) AS foreign_keys
FROM sys.foreign_keys WHERE OBJECT_SCHEMA_NAME(parent_object_id) = 'dw'
GROUP BY OBJECT_NAME(parent_object_id) ORDER BY 1;

-- 5) The audit rows: three SUCCESS lines with real durations
SELECT TOP 3 * FROM audit.load_log ORDER BY load_id DESC;