USE PayerPulse;
GO

/* ===================== Data quality framework =====================
   audit.dq_rule   - the catalogue of rules (each rule is a SELECT that sets @checked and @failed)
   audit.dq_run    - one row per execution of the whole rule set
   audit.dq_result - one row per rule per run
   Status: PASS (0 failures) | FAIL (critical rule broken) | WARN | INFO | ERROR (rule could not run)
   =================================================================== */

IF OBJECT_ID(N'audit.dq_rule', N'U') IS NULL
CREATE TABLE audit.dq_rule (
    rule_id      VARCHAR(8)    NOT NULL CONSTRAINT PK_dq_rule PRIMARY KEY,
    rule_name    VARCHAR(120)  NOT NULL,
    layer_name   VARCHAR(10)   NOT NULL,
    table_name   VARCHAR(60)   NOT NULL,
    dq_dimension VARCHAR(20)   NOT NULL,
    severity     VARCHAR(8)    NOT NULL CONSTRAINT CK_dq_rule_severity CHECK (severity IN ('CRITICAL','WARN','INFO')),
    description  VARCHAR(400)  NOT NULL,
    check_sql    NVARCHAR(MAX) NOT NULL,
    is_active    BIT           NOT NULL CONSTRAINT DF_dq_rule_active DEFAULT 1
);
GO
IF OBJECT_ID(N'audit.dq_run', N'U') IS NULL
CREATE TABLE audit.dq_run (
    run_id      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dq_run PRIMARY KEY,
    started_at  DATETIME2(0) NOT NULL CONSTRAINT DF_dq_run_started DEFAULT SYSUTCDATETIME(),
    finished_at DATETIME2(0) NULL,
    rules_run   INT NULL, rules_pass INT NULL, rules_warn INT NULL,
    rules_fail  INT NULL, rules_info INT NULL, rules_error INT NULL
);
GO
IF OBJECT_ID(N'audit.dq_result', N'U') IS NULL
CREATE TABLE audit.dq_result (
    result_id     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dq_result PRIMARY KEY,
    run_id        INT          NOT NULL CONSTRAINT FK_dq_result_run REFERENCES audit.dq_run(run_id),
    rule_id       VARCHAR(8)   NOT NULL,
    rows_checked  BIGINT       NULL,
    rows_failed   BIGINT       NULL,
    failed_pct    DECIMAL(9,4) NULL,
    status        VARCHAR(6)   NOT NULL,
    duration_ms   INT          NULL,
    error_message NVARCHAR(2000) NULL
);
GO

/* ---------- the rules (re-running this script refreshes the catalogue; results history is kept) ---------- */
DELETE FROM audit.dq_rule;
INSERT INTO audit.dq_rule (rule_id, rule_name, layer_name, table_name, dq_dimension, severity, description, check_sql) VALUES
('REC01', N'fact_claim row count equals staged claims', 'dw', 'fact_claim', 'reconciliation', 'CRITICAL', N'Distinct inpatient + outpatient claim ids plus carrier claims in staging must equal rows in dw.fact_claim.',
    N'SELECT @checked = e.n, @failed = ABS(e.n - g.n) FROM (SELECT (SELECT COUNT(DISTINCT clm_id) FROM stg.inpatient_claim) + (SELECT COUNT(DISTINCT clm_id) FROM stg.outpatient_claim) + (SELECT COUNT_BIG(*) FROM stg.carrier_claim) AS n) e CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM dw.fact_claim) g'),
('REC02', N'Medicare paid total equals staging', 'dw', 'fact_claim', 'reconciliation', 'CRITICAL', N'Sum of Medicare paid across all claim types in dw.fact_claim must equal the staged payment totals (all segments, all carrier lines).',
    N'SELECT @checked = 1, @failed = CASE WHEN s.v <> d.v THEN 1 ELSE 0 END FROM (SELECT (SELECT SUM(clm_pmt_amt) FROM stg.inpatient_claim) + (SELECT SUM(clm_pmt_amt) FROM stg.outpatient_claim) + (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line) AS v) s CROSS JOIN (SELECT SUM(medicare_paid_amt) AS v FROM dw.fact_claim) d'),
('REC03', N'fact_claim_line row count equals staged lines', 'dw', 'fact_claim_line', 'reconciliation', 'CRITICAL', N'Rows in dw.fact_claim_line must equal rows in stg.carrier_line.',
    N'SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.carrier_line), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.carrier_line) - (SELECT COUNT_BIG(*) FROM dw.fact_claim_line))'),
('REC04', N'Carrier line payments equal staging', 'dw', 'fact_claim_line', 'reconciliation', 'CRITICAL', N'Total line payment in dw.fact_claim_line must equal the staged carrier line payment total.',
    N'SELECT @checked = 1, @failed = CASE WHEN (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line) <> (SELECT SUM(line_payment_amt) FROM dw.fact_claim_line) THEN 1 ELSE 0 END'),
('REC05', N'fact_rx_event row count equals staged events', 'dw', 'fact_rx_event', 'reconciliation', 'CRITICAL', N'Rows in dw.fact_rx_event must equal rows in stg.pde_event.',
    N'SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.pde_event), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.pde_event) - (SELECT COUNT_BIG(*) FROM dw.fact_rx_event))'),
('REC06', N'Rx total cost equals staging', 'dw', 'fact_rx_event', 'reconciliation', 'CRITICAL', N'Total drug cost in dw.fact_rx_event must equal the staged total.',
    N'SELECT @checked = 1, @failed = CASE WHEN (SELECT SUM(total_rx_cost_amt) FROM stg.pde_event) <> (SELECT SUM(total_rx_cost_amt) FROM dw.fact_rx_event) THEN 1 ELSE 0 END'),
('REC07', N'fact_member_year row count equals staged member-years', 'dw', 'fact_member_year', 'reconciliation', 'CRITICAL', N'Rows in dw.fact_member_year must equal rows in stg.beneficiary.',
    N'SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.beneficiary), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.beneficiary) - (SELECT COUNT_BIG(*) FROM dw.fact_member_year))'),
('REC08', N'Carrier claim totals equal the sum of their lines', 'dw', 'fact_claim', 'reconciliation', 'CRITICAL', N'For every carrier claim, medicare_paid_amt must equal the sum of its service-line payments.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN ISNULL(c.medicare_paid_amt, 0) <> ISNULL(l.s, 0) THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c LEFT JOIN (SELECT claim_key, SUM(line_payment_amt) AS s FROM dw.fact_claim_line GROUP BY claim_key) l ON l.claim_key = c.claim_key WHERE c.claim_type = ''CARRIER'''),
('CMP01', N'Outpatient claims without dates', 'dw', 'fact_claim', 'completeness', 'WARN', N'Outpatient claims that exist only as a segment-2 record have no from/through date and cannot be placed in time.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN from_date_key IS NULL THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''OUTPATIENT'''),
('CMP02', N'Inpatient claims without a principal diagnosis', 'dw', 'fact_claim', 'completeness', 'WARN', N'Inpatient claims with no first diagnosis code.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN principal_dx_key IS NULL THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'''),
('CMP03', N'Inpatient claims without a DRG', 'dw', 'fact_claim', 'completeness', 'WARN', N'Inpatient claims with no DRG code (the placeholder OTH is counted separately in VAL10).',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN drg_key IS NULL THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'''),
('CMP04', N'Carrier lines with neither NPI nor HCPCS', 'dw', 'fact_claim_line', 'completeness', 'WARN', N'Service lines kept for their dollars that carry no provider NPI and no procedure code.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN is_unidentified_line = 1 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim_line'),
('CMP05', N'Members without a birth date', 'dw', 'dim_beneficiary', 'completeness', 'CRITICAL', N'Every member needs a birth date for age-based reporting.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN birth_date IS NULL THEN 1 ELSE 0 END), 0) FROM dw.dim_beneficiary'),
('CMP06', N'Institutional claims without a facility', 'dw', 'fact_claim', 'completeness', 'WARN', N'Inpatient and outpatient claims with no facility (provider institution).',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN facility_key IS NULL THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type IN (''INPATIENT'',''OUTPATIENT'')'),
('VAL01', N'Discharge before admission', 'dw', 'fact_claim', 'validity', 'CRITICAL', N'Inpatient claims where the discharge date precedes the admission date.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN discharge_date_key < admit_date_key THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'' AND admit_date_key IS NOT NULL AND discharge_date_key IS NOT NULL'),
('VAL02', N'Through-date before from-date', 'dw', 'fact_claim', 'validity', 'CRITICAL', N'Claims whose end date is earlier than their start date.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN thru_date_key < from_date_key THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE from_date_key IS NOT NULL AND thru_date_key IS NOT NULL'),
('VAL03', N'Claim through-date outside 2008-2010', 'dw', 'fact_claim', 'validity', 'WARN', N'The CMS manual assigns a claim to the year of its through-date; dates outside 2008-2010 are unexpected.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN thru_date_key NOT BETWEEN 20080101 AND 20101231 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE thru_date_key IS NOT NULL'),
('VAL04', N'Claims with a negative payment (adjustments)', 'dw', 'fact_claim', 'validity', 'INFO', N'Claims with at least one negative payment segment or line; payment totals are net of these.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN is_adjustment = 1 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim'),
('VAL05', N'Length of stay differs from utilization days', 'dw', 'fact_claim', 'validity', 'WARN', N'Calendar days between admission and discharge versus the reported utilization day count.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN los_days <> utilization_days THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'' AND los_days IS NOT NULL AND utilization_days IS NOT NULL'),
('VAL06', N'Admission date differs from claim from-date', 'dw', 'fact_claim', 'validity', 'WARN', N'Inpatient claims where the admission date and the claim start date disagree.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN admit_date_key <> from_date_key THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'' AND admit_date_key IS NOT NULL AND from_date_key IS NOT NULL'),
('VAL07', N'Implausible length of stay', 'dw', 'fact_claim', 'validity', 'WARN', N'Inpatient stays shorter than 0 or longer than 365 days.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN los_days < 0 OR los_days > 365 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim WHERE claim_type = ''INPATIENT'' AND los_days IS NOT NULL'),
('VAL08', N'Death date before birth date', 'dw', 'dim_beneficiary', 'validity', 'CRITICAL', N'Members whose death date precedes their birth date.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN death_date < birth_date THEN 1 ELSE 0 END), 0) FROM dw.dim_beneficiary WHERE death_date IS NOT NULL AND birth_date IS NOT NULL'),
('VAL09', N'Implausible age (over 110 at end of 2010)', 'dw', 'dim_beneficiary', 'validity', 'WARN', N'Members born before 1900-12-31.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN birth_date < ''19001231'' THEN 1 ELSE 0 END), 0) FROM dw.dim_beneficiary WHERE birth_date IS NOT NULL'),
('VAL10', N'Placeholder DRG codes (OTH)', 'dw', 'fact_claim', 'validity', 'INFO', N'Inpatient claims carrying the placeholder DRG OTH, excluded from DRG-level KPIs.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN d.is_placeholder = 1 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c LEFT JOIN dw.dim_drg d ON d.drg_key = c.drg_key WHERE c.claim_type = ''INPATIENT'''),
('VAL11', N'Placeholder NDC codes (OTHER)', 'dw', 'fact_rx_event', 'validity', 'INFO', N'Prescription events carrying the placeholder NDC OTHER, excluded from drug-level KPIs.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN ndc_is_other = 1 THEN 1 ELSE 0 END), 0) FROM dw.fact_rx_event'),
('VAL12', N'Rx service date outside 2008-2010', 'dw', 'fact_rx_event', 'validity', 'WARN', N'Prescription fills dated outside the 2008-2010 study window.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN service_date_key NOT BETWEEN 20080101 AND 20101231 THEN 1 ELSE 0 END), 0) FROM dw.fact_rx_event WHERE service_date_key IS NOT NULL'),
('VAL13', N'Coverage months above 12', 'dw', 'fact_member_year', 'validity', 'CRITICAL', N'Member-years reporting more than 12 months of Part A, Part B, HMO or Part D coverage.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN part_a_months > 12 OR part_b_months > 12 OR hmo_months > 12 OR part_d_months > 12 THEN 1 ELSE 0 END), 0) FROM dw.fact_member_year'),
('CON01', N'Claims dated after the member''s death', 'dw', 'fact_claim', 'consistency', 'WARN', N'Claims whose start date is after the member''s recorded death date.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN b.death_date IS NOT NULL AND c.from_date_key > CONVERT(int, CONVERT(char(8), b.death_date, 112)) THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c JOIN dw.dim_beneficiary b ON b.beneficiary_key = c.beneficiary_key WHERE c.from_date_key IS NOT NULL'),
('CON02', N'Prescription fills after the member''s death', 'dw', 'fact_rx_event', 'consistency', 'WARN', N'Part D fills dated after the member''s recorded death date.',
    N'SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN b.death_date IS NOT NULL AND r.service_date_key > CONVERT(int, CONVERT(char(8), b.death_date, 112)) THEN 1 ELSE 0 END), 0) FROM dw.fact_rx_event r JOIN dw.dim_beneficiary b ON b.beneficiary_key = r.beneficiary_key WHERE r.service_date_key IS NOT NULL');
GO

/* ---------- runner ---------- */
CREATE OR ALTER PROCEDURE audit.usp_run_dq
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id INT, @rule_id VARCHAR(8), @severity VARCHAR(8), @sql NVARCHAR(MAX);
    DECLARE @checked BIGINT, @failed BIGINT, @status VARCHAR(6), @err NVARCHAR(2000), @t DATETIME2(3);

    INSERT INTO audit.dq_run DEFAULT VALUES;
    SET @run_id = SCOPE_IDENTITY();

    DECLARE rule_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT rule_id, severity, check_sql FROM audit.dq_rule WHERE is_active = 1 ORDER BY rule_id;
    OPEN rule_cur;
    FETCH NEXT FROM rule_cur INTO @rule_id, @severity, @sql;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @t = SYSUTCDATETIME();
        SET @checked = NULL; SET @failed = NULL; SET @err = NULL;
        BEGIN TRY
            EXEC sys.sp_executesql @sql, N'@checked BIGINT OUTPUT, @failed BIGINT OUTPUT',
                 @checked = @checked OUTPUT, @failed = @failed OUTPUT;
            SET @status = CASE WHEN ISNULL(@failed, 0) = 0 THEN 'PASS'
                               WHEN @severity = 'CRITICAL' THEN 'FAIL'
                               WHEN @severity = 'WARN' THEN 'WARN'
                               ELSE 'INFO' END;
        END TRY
        BEGIN CATCH
            SET @status = 'ERROR';
            SET @err = LEFT(ERROR_MESSAGE(), 2000);
        END CATCH

        INSERT INTO audit.dq_result (run_id, rule_id, rows_checked, rows_failed, failed_pct, status, duration_ms, error_message)
        VALUES (@run_id, @rule_id, @checked, @failed,
                CASE WHEN @checked > 0 THEN CAST(100.0 * ISNULL(@failed, 0) / @checked AS DECIMAL(9,4)) END,
                @status, DATEDIFF(millisecond, @t, SYSUTCDATETIME()), @err);

        FETCH NEXT FROM rule_cur INTO @rule_id, @severity, @sql;
    END
    CLOSE rule_cur;
    DEALLOCATE rule_cur;

    UPDATE audit.dq_run
    SET finished_at = SYSUTCDATETIME(),
        rules_run   = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id),
        rules_pass  = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id AND status = 'PASS'),
        rules_warn  = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id AND status = 'WARN'),
        rules_fail  = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id AND status = 'FAIL'),
        rules_info  = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id AND status = 'INFO'),
        rules_error = (SELECT COUNT(*) FROM audit.dq_result WHERE run_id = @run_id AND status = 'ERROR')
    WHERE run_id = @run_id;

    SELECT r.rule_id, r.rule_name, r.severity, x.rows_checked, x.rows_failed, x.failed_pct, x.status, x.duration_ms
    FROM audit.dq_result x
    JOIN audit.dq_rule r ON r.rule_id = x.rule_id
    WHERE x.run_id = @run_id
    ORDER BY CASE x.status WHEN 'ERROR' THEN 0 WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END, r.rule_id;
END;
GO

/* ---------- view for the Power BI data quality monitor: the latest completed run ---------- */
CREATE OR ALTER VIEW audit.v_dq_latest AS
SELECT r.rule_id, r.rule_name, r.layer_name, r.table_name, r.dq_dimension, r.severity, r.description,
       x.run_id, run.started_at, x.rows_checked, x.rows_failed, x.failed_pct, x.status, x.duration_ms, x.error_message
FROM audit.dq_result x
JOIN audit.dq_rule r  ON r.rule_id = x.rule_id
JOIN audit.dq_run run ON run.run_id = x.run_id
WHERE x.run_id = (SELECT MAX(run_id) FROM audit.dq_run WHERE finished_at IS NOT NULL);
GO


USE PayerPulse;
EXEC audit.usp_run_dq;

SELECT * FROM audit.dq_run ORDER BY run_id DESC;
SELECT status, COUNT(*) AS rules FROM audit.v_dq_latest GROUP BY status;