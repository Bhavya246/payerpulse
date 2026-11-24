SELECT segment, COUNT(*) AS rows_with_oth FROM stg.inpatient_claim WHERE clm_drg_cd = 'OTH' GROUP BY segment;

USE PayerPulse;
BEGIN TRAN;

UPDATE TOP (1) dw.fact_claim
SET from_date_key = 20081231, thru_date_key = 20080101     -- end date before start date
WHERE claim_type = 'INPATIENT';

DECLARE @sql NVARCHAR(MAX) = (SELECT check_sql FROM audit.dq_rule WHERE rule_id = 'VAL02');
DECLARE @checked BIGINT, @failed BIGINT;
EXEC sys.sp_executesql @sql, N'@checked BIGINT OUTPUT, @failed BIGINT OUTPUT',
     @checked = @checked OUTPUT, @failed = @failed OUTPUT;
SELECT 'VAL02 with one deliberately broken claim' AS test, @checked AS rows_checked, @failed AS rows_failed;  -- expect 1

ROLLBACK;
SELECT @@TRANCOUNT AS open_transactions;   -- expect 0

USE PayerPulse;

-- 1) How do the coverage months combine?
SELECT coverage_year, coverage_pattern, hmo, COUNT(*) AS member_years,
       SUM(CAST(part_a_months AS int)) AS sum_part_a_months,
       SUM(CAST(part_b_months AS int)) AS sum_part_b_months,
       SUM(CAST(hmo_months AS int))    AS sum_hmo_months
FROM (
    SELECT coverage_year, part_a_months, part_b_months, hmo_months,
           CASE WHEN part_a_months = 12 AND part_b_months = 12 THEN 'A+B full year'
                WHEN part_a_months = 0 AND part_b_months = 0   THEN 'No A/B coverage'
                WHEN part_a_months = part_b_months             THEN 'A = B (partial)'
                ELSE 'A <> B' END AS coverage_pattern,
           CASE WHEN hmo_months > 0 THEN 'some HMO' ELSE 'no HMO' END AS hmo
    FROM dw.fact_member_year
) x
GROUP BY coverage_year, coverage_pattern, hmo
ORDER BY coverage_year, coverage_pattern, hmo;

-- 2) Do members with no Part A/B coverage still have claims?
;WITH cl AS (
    SELECT beneficiary_key, thru_date_key / 10000 AS yr, COUNT(*) AS n
    FROM dw.fact_claim WHERE thru_date_key IS NOT NULL
    GROUP BY beneficiary_key, thru_date_key / 10000
)
SELECT my.coverage_year, COUNT(*) AS member_years_no_AB_coverage,
       SUM(CASE WHEN cl.n IS NOT NULL THEN 1 ELSE 0 END) AS with_claims_that_year
FROM dw.fact_member_year my
LEFT JOIN cl ON cl.beneficiary_key = my.beneficiary_key AND cl.yr = my.coverage_year
WHERE my.part_a_months = 0 AND my.part_b_months = 0
GROUP BY my.coverage_year
ORDER BY my.coverage_year;

USE PayerPulse;

-- 1) How do the coverage months combine?
SELECT coverage_year, coverage_pattern, hmo, COUNT(*) AS member_years,
       SUM(CAST(part_a_months AS int)) AS sum_part_a_months,
       SUM(CAST(part_b_months AS int)) AS sum_part_b_months,
       SUM(CAST(hmo_months AS int))    AS sum_hmo_months
FROM (
    SELECT coverage_year, part_a_months, part_b_months, hmo_months,
           CASE WHEN part_a_months = 12 AND part_b_months = 12 THEN 'A+B full year'
                WHEN part_a_months = 0 AND part_b_months = 0   THEN 'No A/B coverage'
                WHEN part_a_months = part_b_months             THEN 'A = B (partial)'
                ELSE 'A <> B' END AS coverage_pattern,
           CASE WHEN hmo_months > 0 THEN 'some HMO' ELSE 'no HMO' END AS hmo
    FROM dw.fact_member_year
) x
GROUP BY coverage_year, coverage_pattern, hmo
ORDER BY coverage_year, coverage_pattern, hmo;

-- 2) Do members with no Part A/B coverage still have claims?
;WITH cl AS (
    SELECT beneficiary_key, thru_date_key / 10000 AS yr, COUNT(*) AS n
    FROM dw.fact_claim WHERE thru_date_key IS NOT NULL
    GROUP BY beneficiary_key, thru_date_key / 10000
)
SELECT my.coverage_year, COUNT(*) AS member_years_no_AB_coverage,
       SUM(CASE WHEN cl.n IS NOT NULL THEN 1 ELSE 0 END) AS with_claims_that_year
FROM dw.fact_member_year my
LEFT JOIN cl ON cl.beneficiary_key = my.beneficiary_key AND cl.yr = my.coverage_year
WHERE my.part_a_months = 0 AND my.part_b_months = 0
GROUP BY my.coverage_year
ORDER BY my.coverage_year;

USE PayerPulse;

-- A) Do members with HMO months generate fewer fee-for-service claims? (full-year A+B members only)
;WITH cl AS (
    SELECT beneficiary_key, thru_date_key / 10000 AS yr, COUNT(*) AS n, SUM(medicare_paid_amt) AS paid
    FROM dw.fact_claim WHERE thru_date_key IS NOT NULL
    GROUP BY beneficiary_key, thru_date_key / 10000
)
SELECT my.coverage_year,
       CASE WHEN my.hmo_months = 0 THEN '0 HMO months'
            WHEN my.hmo_months BETWEEN 1 AND 11 THEN '1-11 HMO months' ELSE '12 HMO months' END AS hmo_group,
       COUNT(*) AS member_years,
       AVG(CAST(ISNULL(cl.n, 0) AS float))    AS avg_claims_per_member_year,
       AVG(CAST(ISNULL(cl.paid, 0) AS float)) AS avg_medicare_paid_per_member_year
FROM dw.fact_member_year my
LEFT JOIN cl ON cl.beneficiary_key = my.beneficiary_key AND cl.yr = my.coverage_year
WHERE my.part_a_months = 12 AND my.part_b_months = 12
GROUP BY my.coverage_year,
         CASE WHEN my.hmo_months = 0 THEN '0 HMO months'
              WHEN my.hmo_months BETWEEN 1 AND 11 THEN '1-11 HMO months' ELSE '12 HMO months' END
ORDER BY my.coverage_year, hmo_group;

-- B) Who are the member-years with no Part A/B coverage? (dead before the year, died in it, or alive?)
SELECT my.coverage_year, COUNT(*) AS no_AB_member_years,
       SUM(CASE WHEN b.death_date < DATEFROMPARTS(my.coverage_year, 1, 1) THEN 1 ELSE 0 END) AS died_before_year,
       SUM(CASE WHEN b.death_date >= DATEFROMPARTS(my.coverage_year, 1, 1)
                 AND b.death_date <= DATEFROMPARTS(my.coverage_year, 12, 31) THEN 1 ELSE 0 END) AS died_in_year,
       SUM(CASE WHEN b.death_date IS NULL THEN 1 ELSE 0 END) AS alive_all_period
FROM dw.fact_member_year my
JOIN dw.dim_beneficiary b ON b.beneficiary_key = my.beneficiary_key
WHERE my.part_a_months = 0 AND my.part_b_months = 0
GROUP BY my.coverage_year ORDER BY my.coverage_year;

-- C) Members who died during a year: do their coverage months stop at death?
SELECT my.coverage_year, COUNT(*) AS died_in_year,
       AVG(CAST(my.part_a_months AS float)) AS avg_part_a_months,
       SUM(CASE WHEN my.part_a_months = 12 THEN 1 ELSE 0 END) AS still_12_months
FROM dw.fact_member_year my
JOIN dw.dim_beneficiary b ON b.beneficiary_key = my.beneficiary_key
WHERE b.death_date >= DATEFROMPARTS(my.coverage_year, 1, 1) AND b.death_date <= DATEFROMPARTS(my.coverage_year, 12, 31)
GROUP BY my.coverage_year ORDER BY my.coverage_year;