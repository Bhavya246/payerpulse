SELECT 'inpatient' AS tbl, COUNT_BIG(*) AS total_rows, COUNT(DISTINCT clm_id) AS distinct_claim_ids,
       COUNT(DISTINCT CONCAT(clm_id,'|',segment)) AS distinct_claim_segment
FROM raw.inpatient_claims
UNION ALL
SELECT 'outpatient', COUNT_BIG(*), COUNT(DISTINCT clm_id), COUNT(DISTINCT CONCAT(clm_id,'|',segment))
FROM raw.outpatient_claims
UNION ALL
SELECT 'carrier', COUNT_BIG(*), COUNT(DISTINCT clm_id), NULL FROM raw.carrier_claims
UNION ALL
SELECT 'pde', COUNT_BIG(*), COUNT(DISTINCT pde_id), NULL FROM raw.prescription_drug_events;

SELECT 'inpatient' AS tbl,
       SUM(CASE WHEN clm_from_dt IS NULL THEN 1 ELSE 0 END) AS from_null,
       SUM(CASE WHEN clm_from_dt IS NOT NULL AND TRY_CONVERT(date, clm_from_dt, 112) IS NULL THEN 1 ELSE 0 END) AS from_bad,
       SUM(CASE WHEN TRY_CONVERT(date, clm_thru_dt, 112) < TRY_CONVERT(date, clm_from_dt, 112) THEN 1 ELSE 0 END) AS thru_before_from,
       SUM(CASE WHEN TRY_CONVERT(date, nch_bene_dschrg_dt, 112) < TRY_CONVERT(date, clm_admsn_dt, 112) THEN 1 ELSE 0 END) AS discharge_before_admit
FROM raw.inpatient_claims
UNION ALL
SELECT 'outpatient',
       SUM(CASE WHEN clm_from_dt IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN clm_from_dt IS NOT NULL AND TRY_CONVERT(date, clm_from_dt, 112) IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN TRY_CONVERT(date, clm_thru_dt, 112) < TRY_CONVERT(date, clm_from_dt, 112) THEN 1 ELSE 0 END), NULL
FROM raw.outpatient_claims
UNION ALL
SELECT 'carrier',
       SUM(CASE WHEN clm_from_dt IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN clm_from_dt IS NOT NULL AND TRY_CONVERT(date, clm_from_dt, 112) IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN TRY_CONVERT(date, clm_thru_dt, 112) < TRY_CONVERT(date, clm_from_dt, 112) THEN 1 ELSE 0 END), NULL
FROM raw.carrier_claims;

SELECT 'inpatient clm_pmt_amt' AS col,
       SUM(CASE WHEN clm_pmt_amt IS NOT NULL AND TRY_CONVERT(decimal(12,2), clm_pmt_amt) IS NULL THEN 1 ELSE 0 END) AS not_numeric,
       SUM(CASE WHEN TRY_CONVERT(decimal(12,2), clm_pmt_amt) < 0 THEN 1 ELSE 0 END) AS negative
FROM raw.inpatient_claims
UNION ALL
SELECT 'outpatient clm_pmt_amt',
       SUM(CASE WHEN clm_pmt_amt IS NOT NULL AND TRY_CONVERT(decimal(12,2), clm_pmt_amt) IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN TRY_CONVERT(decimal(12,2), clm_pmt_amt) < 0 THEN 1 ELSE 0 END)
FROM raw.outpatient_claims
UNION ALL
SELECT 'pde tot_rx_cst_amt',
       SUM(CASE WHEN tot_rx_cst_amt IS NOT NULL AND TRY_CONVERT(decimal(12,2), tot_rx_cst_amt) IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN TRY_CONVERT(decimal(12,2), tot_rx_cst_amt) < 0 THEN 1 ELSE 0 END)
FROM raw.prescription_drug_events;

SET STATISTICS TIME ON;

SELECT 'inpatient' AS tbl, COUNT_BIG(*) AS orphan_rows FROM raw.inpatient_claims c
WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary_summary b WHERE b.desynpuf_id = c.desynpuf_id)
UNION ALL
SELECT 'outpatient', COUNT_BIG(*) FROM raw.outpatient_claims c
WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary_summary b WHERE b.desynpuf_id = c.desynpuf_id)
UNION ALL
SELECT 'pde', COUNT_BIG(*) FROM raw.prescription_drug_events c
WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary_summary b WHERE b.desynpuf_id = c.desynpuf_id);

SELECT LEN(prod_srvc_id) AS ndc_length, COUNT_BIG(*) AS rows_ FROM raw.prescription_drug_events GROUP BY LEN(prod_srvc_id) ORDER BY 1;
SELECT TOP 10 clm_drg_cd, COUNT(*) AS n FROM raw.inpatient_claims GROUP BY clm_drg_cd ORDER BY n DESC;
SELECT sp_chf, COUNT(*) AS n FROM raw.beneficiary_summary GROUP BY sp_chf;

SELECT 'inpatient' AS tbl, segment, COUNT(*) AS n,
       SUM(CASE WHEN clm_from_dt IS NULL THEN 1 ELSE 0 END) AS from_null,
       SUM(CASE WHEN clm_thru_dt IS NULL THEN 1 ELSE 0 END) AS thru_null
FROM raw.inpatient_claims GROUP BY segment
UNION ALL
SELECT 'outpatient', segment, COUNT(*),
       SUM(CASE WHEN clm_from_dt IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN clm_thru_dt IS NULL THEN 1 ELSE 0 END)
FROM raw.outpatient_claims GROUP BY segment
ORDER BY tbl, segment;

SELECT desynpuf_id, clm_id, segment, clm_from_dt, clm_thru_dt, prvdr_num, clm_pmt_amt
FROM raw.outpatient_claims
WHERE clm_id IN (SELECT TOP 5 clm_id FROM raw.outpatient_claims GROUP BY clm_id HAVING COUNT(*) > 1)
ORDER BY clm_id, segment;

SELECT TOP 10 clm_id, segment, clm_from_dt, clm_thru_dt, clm_pmt_amt, nch_prmry_pyr_clm_pd_amt
FROM raw.outpatient_claims
WHERE TRY_CONVERT(decimal(12,2), clm_pmt_amt) < 0
ORDER BY TRY_CONVERT(decimal(12,2), clm_pmt_amt);

SELECT TOP 10 pde_id, prod_srvc_id, srvc_dt, tot_rx_cst_amt
FROM raw.prescription_drug_events
WHERE LEN(prod_srvc_id) <> 11;