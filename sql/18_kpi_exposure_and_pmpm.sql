USE PayerPulse;
GO

/* ===== Exposure view: member-year months of risk, per service category =====
   Rules (see docs/kpi_catalog.md):
   - months alive = 12, or the month of death in the year of death (0 if dead before the year)
   - inpatient exposure       = MIN(Part A months, months alive)
   - outpatient/carrier       = MIN(Part B months, months alive)
   - Part D (Rx) exposure     = MIN(Part D months, months alive)
   - HMO months are NOT subtracted (profiling showed HMO members have the same fee-for-service claims) */
CREATE OR ALTER VIEW dw.v_member_exposure AS
SELECT my.beneficiary_key, my.coverage_year, my.state_code, my.county_code, my.esrd_flag,
       b.sex_desc, b.race_desc,
       my.coverage_year - YEAR(b.birth_date) AS age_in_year,
       a.months_alive,
       m.ip_member_months, m.opcar_member_months, m.rx_member_months,
       my.has_alzheimers, my.has_chf, my.has_ckd, my.has_cancer, my.has_copd, my.has_depression,
       my.has_diabetes, my.has_ihd, my.has_osteoporosis, my.has_ra_oa, my.has_stroke_tia
FROM dw.fact_member_year my
JOIN dw.dim_beneficiary b ON b.beneficiary_key = my.beneficiary_key
CROSS APPLY (SELECT CASE WHEN b.death_date IS NULL THEN 12
                         WHEN YEAR(b.death_date) < my.coverage_year THEN 0
                         WHEN YEAR(b.death_date) = my.coverage_year THEN MONTH(b.death_date)
                         ELSE 12 END AS months_alive) a
CROSS APPLY (SELECT CASE WHEN ISNULL(my.part_a_months, 0) < a.months_alive THEN ISNULL(my.part_a_months, 0) ELSE a.months_alive END AS ip_member_months,
                    CASE WHEN ISNULL(my.part_b_months, 0) < a.months_alive THEN ISNULL(my.part_b_months, 0) ELSE a.months_alive END AS opcar_member_months,
                    CASE WHEN ISNULL(my.part_d_months, 0) < a.months_alive THEN ISNULL(my.part_d_months, 0) ELSE a.months_alive END AS rx_member_months) m;
GO

/* ===== PMPM by year and service category (Medicare paid per member month) =====
   Numerator and denominator are aligned: a claim counts only if the member has exposure in that category that year.
   Claims without dates, or from members with no exposure, are left out here and shown in the bridge check. */
CREATE OR ALTER VIEW dw.v_kpi_pmpm AS
WITH mm AS (
    SELECT coverage_year,
           SUM(CAST(ip_member_months AS bigint))    AS ip_mm,
           SUM(CAST(opcar_member_months AS bigint)) AS opcar_mm,
           SUM(CAST(rx_member_months AS bigint))    AS rx_mm
    FROM dw.v_member_exposure
    GROUP BY coverage_year
), med AS (
    SELECT c.claim_type, c.thru_date_key / 10000 AS coverage_year,
           COUNT_BIG(*) AS claims, SUM(c.medicare_paid_amt) AS paid_amt
    FROM dw.fact_claim c
    JOIN dw.v_member_exposure e
      ON e.beneficiary_key = c.beneficiary_key AND e.coverage_year = c.thru_date_key / 10000
    WHERE c.thru_date_key IS NOT NULL
      AND ((c.claim_type = 'INPATIENT' AND e.ip_member_months > 0)
        OR (c.claim_type <> 'INPATIENT' AND e.opcar_member_months > 0))
    GROUP BY c.claim_type, c.thru_date_key / 10000
), rx AS (
    SELECT r.service_date_key / 10000 AS coverage_year, COUNT_BIG(*) AS events, SUM(r.total_rx_cost_amt) AS paid_amt
    FROM dw.fact_rx_event r
    JOIN dw.v_member_exposure e
      ON e.beneficiary_key = r.beneficiary_key AND e.coverage_year = r.service_date_key / 10000
    WHERE r.service_date_key IS NOT NULL AND e.rx_member_months > 0
    GROUP BY r.service_date_key / 10000
), cat AS (
    SELECT m.coverage_year, CAST(m.claim_type AS VARCHAR(40)) AS service_category,
           m.claims AS claims_or_events, CAST(m.paid_amt AS DECIMAL(18,2)) AS paid_amt,
           CASE WHEN m.claim_type = 'INPATIENT' THEN mm.ip_mm ELSE mm.opcar_mm END AS member_months
    FROM med m JOIN mm ON mm.coverage_year = m.coverage_year
    UNION ALL
    SELECT x.coverage_year, 'PART D RX', x.events, CAST(x.paid_amt AS DECIMAL(18,2)), mm.rx_mm
    FROM rx x JOIN mm ON mm.coverage_year = x.coverage_year
)
SELECT coverage_year, service_category, claims_or_events, paid_amt, member_months,
       CAST(paid_amt / NULLIF(member_months, 0) AS DECIMAL(12,2)) AS pmpm
FROM cat
UNION ALL
SELECT coverage_year, 'TOTAL MEDICAL (IP+OP+CARRIER)', SUM(claims_or_events), SUM(paid_amt), NULL,
       CAST(SUM(paid_amt / NULLIF(member_months, 0)) AS DECIMAL(12,2))
FROM cat
WHERE service_category <> 'PART D RX'
GROUP BY coverage_year;
GO

USE PayerPulse;

-- 1) The PMPM view
SELECT * FROM dw.v_kpi_pmpm ORDER BY coverage_year, service_category;

-- 2) Bridge: every dollar of Medicare paid is either in the PMPM numerator, undated, or excluded for having no exposure
SELECT claim_type, total_paid_in_fact, undated, in_pmpm_numerator,
       total_paid_in_fact - undated - in_pmpm_numerator AS excluded_no_exposure
FROM (
    SELECT c.claim_type,
           SUM(c.medicare_paid_amt) AS total_paid_in_fact,
           SUM(CASE WHEN c.thru_date_key IS NULL THEN c.medicare_paid_amt ELSE 0 END) AS undated,
           SUM(CASE WHEN c.thru_date_key IS NOT NULL
                     AND ((c.claim_type = 'INPATIENT' AND e.ip_member_months > 0)
                       OR (c.claim_type <> 'INPATIENT' AND e.opcar_member_months > 0))
                    THEN c.medicare_paid_amt ELSE 0 END) AS in_pmpm_numerator
    FROM dw.fact_claim c
    LEFT JOIN dw.v_member_exposure e
      ON e.beneficiary_key = c.beneficiary_key AND e.coverage_year = c.thru_date_key / 10000
    GROUP BY c.claim_type
) x
ORDER BY claim_type;