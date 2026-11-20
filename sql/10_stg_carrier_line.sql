USE PayerPulse;
GO

-- Make sure the log is cheap: SIMPLE recovery + a heap loaded WITH (TABLOCK) is minimally logged.
ALTER DATABASE PayerPulse SET RECOVERY SIMPLE;
GO

IF OBJECT_ID(N'stg.carrier_line', N'U') IS NOT NULL DROP TABLE stg.carrier_line;
GO
-- No primary key yet: the key is added AFTER the load so the insert can be minimally logged.
CREATE TABLE stg.carrier_line (
    clm_id      VARCHAR(20) NOT NULL,
    line_number TINYINT     NOT NULL,
    prf_physn_npi VARCHAR(10) NULL,
    tax_num VARCHAR(10) NULL,
    hcpcs_cd VARCHAR(10) NULL,
    line_nch_pmt_amt DECIMAL(12,2) NULL,
    line_bene_ptb_ddctbl_amt DECIMAL(12,2) NULL,
    line_bene_prmry_pyr_pd_amt DECIMAL(12,2) NULL,
    line_coinsrnc_amt DECIMAL(12,2) NULL,
    line_alowd_chrg_amt DECIMAL(12,2) NULL,
    line_prcsg_ind_cd VARCHAR(5) NULL,
    line_icd9_dgns_cd VARCHAR(10) NULL
);
GO
DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;
SELECT @raw_rows = COUNT_BIG(*) FROM raw.carrier_claims;
INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)
VALUES ('stg_load', 'raw.carrier_claims -> stg.carrier_line (unpivot)', @raw_rows);
SET @load_id = SCOPE_IDENTITY();

-- A slot is a real line only if prf_physn_npi or hcpcs_cd is present.
INSERT INTO stg.carrier_line WITH (TABLOCK) (clm_id, line_number, prf_physn_npi, tax_num, hcpcs_cd, line_nch_pmt_amt, line_bene_ptb_ddctbl_amt, line_bene_prmry_pyr_pd_amt, line_coinsrnc_amt, line_alowd_chrg_amt, line_prcsg_ind_cd, line_icd9_dgns_cd)
SELECT c.clm_id, v.n,
       v.c1,
       v.c2,
       v.c3,
       TRY_CONVERT(decimal(12,2), v.c4),
       TRY_CONVERT(decimal(12,2), v.c5),
       TRY_CONVERT(decimal(12,2), v.c6),
       TRY_CONVERT(decimal(12,2), v.c7),
       TRY_CONVERT(decimal(12,2), v.c8),
       v.c9,
       v.c10
FROM raw.carrier_claims c
CROSS APPLY (VALUES
        (1, c.prf_physn_npi_1, c.tax_num_1, c.hcpcs_cd_1, c.line_nch_pmt_amt_1, c.line_bene_ptb_ddctbl_amt_1, c.line_bene_prmry_pyr_pd_amt_1, c.line_coinsrnc_amt_1, c.line_alowd_chrg_amt_1, c.line_prcsg_ind_cd_1, c.line_icd9_dgns_cd_1),
        (2, c.prf_physn_npi_2, c.tax_num_2, c.hcpcs_cd_2, c.line_nch_pmt_amt_2, c.line_bene_ptb_ddctbl_amt_2, c.line_bene_prmry_pyr_pd_amt_2, c.line_coinsrnc_amt_2, c.line_alowd_chrg_amt_2, c.line_prcsg_ind_cd_2, c.line_icd9_dgns_cd_2),
        (3, c.prf_physn_npi_3, c.tax_num_3, c.hcpcs_cd_3, c.line_nch_pmt_amt_3, c.line_bene_ptb_ddctbl_amt_3, c.line_bene_prmry_pyr_pd_amt_3, c.line_coinsrnc_amt_3, c.line_alowd_chrg_amt_3, c.line_prcsg_ind_cd_3, c.line_icd9_dgns_cd_3),
        (4, c.prf_physn_npi_4, c.tax_num_4, c.hcpcs_cd_4, c.line_nch_pmt_amt_4, c.line_bene_ptb_ddctbl_amt_4, c.line_bene_prmry_pyr_pd_amt_4, c.line_coinsrnc_amt_4, c.line_alowd_chrg_amt_4, c.line_prcsg_ind_cd_4, c.line_icd9_dgns_cd_4),
        (5, c.prf_physn_npi_5, c.tax_num_5, c.hcpcs_cd_5, c.line_nch_pmt_amt_5, c.line_bene_ptb_ddctbl_amt_5, c.line_bene_prmry_pyr_pd_amt_5, c.line_coinsrnc_amt_5, c.line_alowd_chrg_amt_5, c.line_prcsg_ind_cd_5, c.line_icd9_dgns_cd_5),
        (6, c.prf_physn_npi_6, c.tax_num_6, c.hcpcs_cd_6, c.line_nch_pmt_amt_6, c.line_bene_ptb_ddctbl_amt_6, c.line_bene_prmry_pyr_pd_amt_6, c.line_coinsrnc_amt_6, c.line_alowd_chrg_amt_6, c.line_prcsg_ind_cd_6, c.line_icd9_dgns_cd_6),
        (7, c.prf_physn_npi_7, c.tax_num_7, c.hcpcs_cd_7, c.line_nch_pmt_amt_7, c.line_bene_ptb_ddctbl_amt_7, c.line_bene_prmry_pyr_pd_amt_7, c.line_coinsrnc_amt_7, c.line_alowd_chrg_amt_7, c.line_prcsg_ind_cd_7, c.line_icd9_dgns_cd_7),
        (8, c.prf_physn_npi_8, c.tax_num_8, c.hcpcs_cd_8, c.line_nch_pmt_amt_8, c.line_bene_ptb_ddctbl_amt_8, c.line_bene_prmry_pyr_pd_amt_8, c.line_coinsrnc_amt_8, c.line_alowd_chrg_amt_8, c.line_prcsg_ind_cd_8, c.line_icd9_dgns_cd_8),
        (9, c.prf_physn_npi_9, c.tax_num_9, c.hcpcs_cd_9, c.line_nch_pmt_amt_9, c.line_bene_ptb_ddctbl_amt_9, c.line_bene_prmry_pyr_pd_amt_9, c.line_coinsrnc_amt_9, c.line_alowd_chrg_amt_9, c.line_prcsg_ind_cd_9, c.line_icd9_dgns_cd_9),
        (10, c.prf_physn_npi_10, c.tax_num_10, c.hcpcs_cd_10, c.line_nch_pmt_amt_10, c.line_bene_ptb_ddctbl_amt_10, c.line_bene_prmry_pyr_pd_amt_10, c.line_coinsrnc_amt_10, c.line_alowd_chrg_amt_10, c.line_prcsg_ind_cd_10, c.line_icd9_dgns_cd_10),
        (11, c.prf_physn_npi_11, c.tax_num_11, c.hcpcs_cd_11, c.line_nch_pmt_amt_11, c.line_bene_ptb_ddctbl_amt_11, c.line_bene_prmry_pyr_pd_amt_11, c.line_coinsrnc_amt_11, c.line_alowd_chrg_amt_11, c.line_prcsg_ind_cd_11, c.line_icd9_dgns_cd_11),
        (12, c.prf_physn_npi_12, c.tax_num_12, c.hcpcs_cd_12, c.line_nch_pmt_amt_12, c.line_bene_ptb_ddctbl_amt_12, c.line_bene_prmry_pyr_pd_amt_12, c.line_coinsrnc_amt_12, c.line_alowd_chrg_amt_12, c.line_prcsg_ind_cd_12, c.line_icd9_dgns_cd_12),
        (13, c.prf_physn_npi_13, c.tax_num_13, c.hcpcs_cd_13, c.line_nch_pmt_amt_13, c.line_bene_ptb_ddctbl_amt_13, c.line_bene_prmry_pyr_pd_amt_13, c.line_coinsrnc_amt_13, c.line_alowd_chrg_amt_13, c.line_prcsg_ind_cd_13, c.line_icd9_dgns_cd_13)
) AS v(n, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10)
WHERE v.c1 IS NOT NULL
   OR v.c3 IS NOT NULL;
SET @loaded = @@ROWCOUNT;

ALTER TABLE stg.carrier_line ADD CONSTRAINT PK_stg_carrier_line PRIMARY KEY CLUSTERED (clm_id, line_number);

-- rows_read = carrier CLAIMS read; rows_loaded = service LINES produced.
UPDATE audit.load_log
SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,
    status = CASE WHEN @loaded > 0 THEN 'SUCCESS' ELSE 'FAILED' END
WHERE load_id = @load_id;
GO

-- Reconciliation. Counts: line slots with a real key in raw vs rows in staging.
-- Dollars: the sum over all 13 slots in raw must equal the staging total (no money dropped with empty slots).
SELECT 'real line slots' AS check_name,
       (SELECT SUM(CASE WHEN prf_physn_npi_1 IS NOT NULL OR hcpcs_cd_1 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_2 IS NOT NULL OR hcpcs_cd_2 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_3 IS NOT NULL OR hcpcs_cd_3 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_4 IS NOT NULL OR hcpcs_cd_4 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_5 IS NOT NULL OR hcpcs_cd_5 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_6 IS NOT NULL OR hcpcs_cd_6 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_7 IS NOT NULL OR hcpcs_cd_7 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_8 IS NOT NULL OR hcpcs_cd_8 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_9 IS NOT NULL OR hcpcs_cd_9 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_10 IS NOT NULL OR hcpcs_cd_10 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_11 IS NOT NULL OR hcpcs_cd_11 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_12 IS NOT NULL OR hcpcs_cd_12 IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN prf_physn_npi_13 IS NOT NULL OR hcpcs_cd_13 IS NOT NULL THEN 1 ELSE 0 END) FROM raw.carrier_claims) AS raw_value,
       (SELECT COUNT_BIG(*) FROM stg.carrier_line) AS stg_value
UNION ALL SELECT 'line_nch_pmt_amt total',
       (SELECT ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_1)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_2)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_3)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_4)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_5)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_6)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_7)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_8)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_9)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_10)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_11)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_12)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_nch_pmt_amt_13)), 0) FROM raw.carrier_claims),
       (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line)
UNION ALL SELECT 'line_alowd_chrg_amt total',
       (SELECT ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_1)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_2)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_3)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_4)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_5)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_6)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_7)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_8)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_9)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_10)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_11)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_12)), 0) + ISNULL(SUM(TRY_CONVERT(decimal(18,2), line_alowd_chrg_amt_13)), 0) FROM raw.carrier_claims),
       (SELECT SUM(line_alowd_chrg_amt) FROM stg.carrier_line);
