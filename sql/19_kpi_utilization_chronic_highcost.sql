USE PayerPulse;
GO

/* ===== Admissions per 1,000 and average length of stay (inpatient) =====
   - an admission is one inpatient claim (header = segment 1), attributed to the year of discharge
   - only members with inpatient exposure (Part A months, capped at death) count
   - admissions per 1,000 = admissions / (inpatient member months / 12) * 1000
   - length of stay = calendar days from admission to discharge (same-day stays count as 0 days) */
CREATE OR ALTER VIEW dw.v_kpi_utilization AS
WITH mm AS (
    SELECT coverage_year, SUM(CAST(ip_member_months AS bigint)) AS ip_mm
    FROM dw.v_member_exposure
    GROUP BY coverage_year
), adm AS (
    SELECT c.discharge_date_key / 10000 AS coverage_year,
           COUNT_BIG(*) AS admissions,
           AVG(CAST(c.los_days AS float)) AS avg_los_days
    FROM dw.fact_claim c
    JOIN dw.v_member_exposure e
      ON e.beneficiary_key = c.beneficiary_key AND e.coverage_year = c.discharge_date_key / 10000
    WHERE c.claim_type = 'INPATIENT' AND c.discharge_date_key IS NOT NULL AND e.ip_member_months > 0
    GROUP BY c.discharge_date_key / 10000
)
SELECT a.coverage_year, a.admissions, mm.ip_mm AS member_months,
       CAST(1000.0 * a.admissions / NULLIF(mm.ip_mm / 12.0, 0) AS DECIMAL(9,2)) AS admits_per_1000,
       CAST(a.avg_los_days AS DECIMAL(9,2)) AS avg_los_days
FROM adm a
JOIN mm ON mm.coverage_year = a.coverage_year;
GO

/* ===== Chronic condition prevalence =====
   Denominator: member-years with any exposure that year. Flags come from the CMS beneficiary summary (1 = yes). */
CREATE OR ALTER VIEW dw.v_kpi_chronic_prevalence AS
SELECT e.coverage_year, c.condition,
       COUNT(c.flag) AS members,
       SUM(CAST(c.flag AS int)) AS members_with_condition,
       CAST(100.0 * SUM(CAST(c.flag AS int)) / NULLIF(COUNT(c.flag), 0) AS DECIMAL(6,2)) AS prevalence_pct
FROM dw.v_member_exposure e
CROSS APPLY (VALUES
    ('Alzheimer / dementia',   e.has_alzheimers),
    ('Heart failure',          e.has_chf),
    ('Chronic kidney disease', e.has_ckd),
    ('Cancer',                 e.has_cancer),
    ('COPD',                   e.has_copd),
    ('Depression',             e.has_depression),
    ('Diabetes',               e.has_diabetes),
    ('Ischemic heart disease', e.has_ihd),
    ('Osteoporosis',           e.has_osteoporosis),
    ('RA / osteoarthritis',    e.has_ra_oa),
    ('Stroke / TIA',           e.has_stroke_tia)
) c(condition, flag)
WHERE e.ip_member_months > 0 OR e.opcar_member_months > 0
GROUP BY e.coverage_year, c.condition;
GO

/* ===== High-cost claimants =====
   High-cost = top 5% of members by Medicare paid (inpatient + outpatient + carrier) in the year,
   among members with any exposure that year (members with no claims count as zero spend). */
CREATE OR ALTER VIEW dw.v_kpi_high_cost AS
WITH spend AS (
    SELECT e.coverage_year, e.beneficiary_key, ISNULL(SUM(c.medicare_paid_amt), 0) AS paid
    FROM dw.v_member_exposure e
    LEFT JOIN dw.fact_claim c
      ON c.beneficiary_key = e.beneficiary_key AND c.thru_date_key / 10000 = e.coverage_year
    WHERE e.ip_member_months > 0 OR e.opcar_member_months > 0
    GROUP BY e.coverage_year, e.beneficiary_key
), ranked AS (
    SELECT coverage_year, beneficiary_key, paid,
           NTILE(20) OVER (PARTITION BY coverage_year ORDER BY paid DESC) AS vigintile
    FROM spend
)
SELECT coverage_year,
       COUNT(*) AS members,
       SUM(CASE WHEN vigintile = 1 THEN 1 ELSE 0 END) AS high_cost_members,
       CAST(SUM(paid) AS DECIMAL(18,2)) AS total_paid,
       CAST(SUM(CASE WHEN vigintile = 1 THEN paid ELSE 0 END) AS DECIMAL(18,2)) AS high_cost_paid,
       CAST(100.0 * SUM(CASE WHEN vigintile = 1 THEN paid ELSE 0 END) / NULLIF(SUM(paid), 0) AS DECIMAL(5,2)) AS high_cost_share_pct
FROM ranked
GROUP BY coverage_year;
GO

USE PayerPulse;
SELECT * FROM dw.v_kpi_utilization ORDER BY coverage_year;
SELECT * FROM dw.v_kpi_chronic_prevalence WHERE coverage_year = 2008 ORDER BY prevalence_pct DESC;
SELECT * FROM dw.v_kpi_high_cost ORDER BY coverage_year;