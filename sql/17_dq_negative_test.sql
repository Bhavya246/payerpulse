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