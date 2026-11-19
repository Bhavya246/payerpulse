SELECT COUNT(*) AS pairs,
       SUM(CASE WHEN s1.clm_admsn_dt = s2.clm_admsn_dt AND s1.nch_bene_dschrg_dt = s2.nch_bene_dschrg_dt THEN 1 ELSE 0 END) AS same_dates,
       SUM(CASE WHEN s2.icd9_dgns_cd_1 IS NOT NULL THEN 1 ELSE 0 END) AS seg2_has_dx,
       SUM(CASE WHEN s2.hcpcs_cd_1 IS NOT NULL THEN 1 ELSE 0 END) AS seg2_has_hcpcs
FROM stg.inpatient_claim s1
JOIN stg.inpatient_claim s2 ON s2.clm_id = s1.clm_id AND s1.segment = 1 AND s2.segment = 2;

USE PayerPulse;
GO
IF OBJECT_ID(N'stg.pde_event', N'U') IS NOT NULL DROP TABLE stg.pde_event;
GO
CREATE TABLE stg.pde_event (
    pde_id             VARCHAR(20)   NOT NULL,
    desynpuf_id        VARCHAR(16)   NOT NULL,
    service_date       DATE          NULL,
    ndc_code           VARCHAR(11)   NULL,
    quantity_dispensed DECIMAL(12,3) NULL,
    days_supply        SMALLINT      NULL,
    patient_pay_amt    DECIMAL(12,2) NULL,
    total_rx_cost_amt  DECIMAL(12,2) NULL,
    ndc_is_other       BIT           NOT NULL,   -- the 'OTHER' placeholder, excluded from drug-level KPIs
    CONSTRAINT PK_stg_pde_event PRIMARY KEY (pde_id)
);
GO

DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;
SELECT @raw_rows = COUNT_BIG(*) FROM raw.prescription_drug_events;

INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)
VALUES ('stg_load', 'raw.prescription_drug_events -> stg.pde_event', @raw_rows);
SET @load_id = SCOPE_IDENTITY();

INSERT INTO stg.pde_event
    (pde_id, desynpuf_id, service_date, ndc_code, quantity_dispensed, days_supply,
     patient_pay_amt, total_rx_cost_amt, ndc_is_other)
SELECT pde_id, desynpuf_id, TRY_CONVERT(date, srvc_dt, 112), prod_srvc_id,
       TRY_CONVERT(decimal(12,3), qty_dspnsd_num), TRY_CONVERT(smallint, days_suply_num),
       TRY_CONVERT(decimal(12,2), ptnt_pay_amt), TRY_CONVERT(decimal(12,2), tot_rx_cst_amt),
       CASE WHEN prod_srvc_id = 'OTHER' THEN 1 ELSE 0 END
FROM raw.prescription_drug_events;
SET @loaded = @@ROWCOUNT;

UPDATE audit.load_log
SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,
    status = CASE WHEN @loaded = @raw_rows THEN 'SUCCESS' ELSE 'FAILED' END
WHERE load_id = @load_id;
GO

-- Conversion check: raw_non_null must equal stg_non_null on every row
SELECT 'srvc_dt' AS col, (SELECT COUNT(srvc_dt) FROM raw.prescription_drug_events) AS raw_non_null, (SELECT COUNT(service_date) FROM stg.pde_event) AS stg_non_null
UNION ALL SELECT 'qty_dspnsd_num', (SELECT COUNT(qty_dspnsd_num) FROM raw.prescription_drug_events), (SELECT COUNT(quantity_dispensed) FROM stg.pde_event)
UNION ALL SELECT 'days_suply_num', (SELECT COUNT(days_suply_num) FROM raw.prescription_drug_events), (SELECT COUNT(days_supply) FROM stg.pde_event)
UNION ALL SELECT 'ptnt_pay_amt',   (SELECT COUNT(ptnt_pay_amt)   FROM raw.prescription_drug_events), (SELECT COUNT(patient_pay_amt)   FROM stg.pde_event)
UNION ALL SELECT 'tot_rx_cst_amt', (SELECT COUNT(tot_rx_cst_amt) FROM raw.prescription_drug_events), (SELECT COUNT(total_rx_cost_amt) FROM stg.pde_event);

SELECT COUNT(*) AS rows_, SUM(CAST(ndc_is_other AS int)) AS ndc_other,
       SUM(CASE WHEN LEN(ndc_code) = 11 THEN 1 ELSE 0 END) AS ndc_11_char
FROM stg.pde_event;

SELECT TOP 1 * FROM audit.load_log ORDER BY load_id DESC;