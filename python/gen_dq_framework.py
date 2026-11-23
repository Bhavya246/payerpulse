from pathlib import Path

OUT_FILE = Path(__file__).resolve().parent.parent / "sql" / "16_dq_framework.sql"

# Every rule is a SELECT that sets two variables: @checked (rows examined) and @failed (rows breaking the rule).
RULES = []
def rule(rid, name, table, dim, sev, desc, sql):
    RULES.append(dict(id=rid, name=name, layer="dw", table=table, dim=dim, sev=sev, desc=desc, sql=sql))

def count_rule(rid, name, table, dim, sev, desc, frm, bad, where=None):
    sql = f"SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN {bad} THEN 1 ELSE 0 END), 0) FROM {frm}"
    if where:
        sql += f" WHERE {where}"
    rule(rid, name, table, dim, sev, desc, sql)

# ---------------- reconciliation: warehouse must equal staging ----------------
rule("REC01", "fact_claim row count equals staged claims", "fact_claim", "reconciliation", "CRITICAL",
     "Distinct inpatient + outpatient claim ids plus carrier claims in staging must equal rows in dw.fact_claim.",
     "SELECT @checked = e.n, @failed = ABS(e.n - g.n) FROM (SELECT (SELECT COUNT(DISTINCT clm_id) FROM stg.inpatient_claim) + (SELECT COUNT(DISTINCT clm_id) FROM stg.outpatient_claim) + (SELECT COUNT_BIG(*) FROM stg.carrier_claim) AS n) e CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM dw.fact_claim) g")
rule("REC02", "Medicare paid total equals staging", "fact_claim", "reconciliation", "CRITICAL",
     "Sum of Medicare paid across all claim types in dw.fact_claim must equal the staged payment totals (all segments, all carrier lines).",
     "SELECT @checked = 1, @failed = CASE WHEN s.v <> d.v THEN 1 ELSE 0 END FROM (SELECT (SELECT SUM(clm_pmt_amt) FROM stg.inpatient_claim) + (SELECT SUM(clm_pmt_amt) FROM stg.outpatient_claim) + (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line) AS v) s CROSS JOIN (SELECT SUM(medicare_paid_amt) AS v FROM dw.fact_claim) d")
rule("REC03", "fact_claim_line row count equals staged lines", "fact_claim_line", "reconciliation", "CRITICAL",
     "Rows in dw.fact_claim_line must equal rows in stg.carrier_line.",
     "SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.carrier_line), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.carrier_line) - (SELECT COUNT_BIG(*) FROM dw.fact_claim_line))")
rule("REC04", "Carrier line payments equal staging", "fact_claim_line", "reconciliation", "CRITICAL",
     "Total line payment in dw.fact_claim_line must equal the staged carrier line payment total.",
     "SELECT @checked = 1, @failed = CASE WHEN (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line) <> (SELECT SUM(line_payment_amt) FROM dw.fact_claim_line) THEN 1 ELSE 0 END")
rule("REC05", "fact_rx_event row count equals staged events", "fact_rx_event", "reconciliation", "CRITICAL",
     "Rows in dw.fact_rx_event must equal rows in stg.pde_event.",
     "SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.pde_event), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.pde_event) - (SELECT COUNT_BIG(*) FROM dw.fact_rx_event))")
rule("REC06", "Rx total cost equals staging", "fact_rx_event", "reconciliation", "CRITICAL",
     "Total drug cost in dw.fact_rx_event must equal the staged total.",
     "SELECT @checked = 1, @failed = CASE WHEN (SELECT SUM(total_rx_cost_amt) FROM stg.pde_event) <> (SELECT SUM(total_rx_cost_amt) FROM dw.fact_rx_event) THEN 1 ELSE 0 END")
rule("REC07", "fact_member_year row count equals staged member-years", "fact_member_year", "reconciliation", "CRITICAL",
     "Rows in dw.fact_member_year must equal rows in stg.beneficiary.",
     "SELECT @checked = (SELECT COUNT_BIG(*) FROM stg.beneficiary), @failed = ABS((SELECT COUNT_BIG(*) FROM stg.beneficiary) - (SELECT COUNT_BIG(*) FROM dw.fact_member_year))")
rule("REC08", "Carrier claim totals equal the sum of their lines", "fact_claim", "reconciliation", "CRITICAL",
     "For every carrier claim, medicare_paid_amt must equal the sum of its service-line payments.",
     "SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN ISNULL(c.medicare_paid_amt, 0) <> ISNULL(l.s, 0) THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c LEFT JOIN (SELECT claim_key, SUM(line_payment_amt) AS s FROM dw.fact_claim_line GROUP BY claim_key) l ON l.claim_key = c.claim_key WHERE c.claim_type = 'CARRIER'")

# ---------------- completeness ----------------
count_rule("CMP01", "Outpatient claims without dates", "fact_claim", "completeness", "WARN",
           "Outpatient claims that exist only as a segment-2 record have no from/through date and cannot be placed in time.",
           "dw.fact_claim", "from_date_key IS NULL", "claim_type = 'OUTPATIENT'")
count_rule("CMP02", "Inpatient claims without a principal diagnosis", "fact_claim", "completeness", "WARN",
           "Inpatient claims with no first diagnosis code.",
           "dw.fact_claim", "principal_dx_key IS NULL", "claim_type = 'INPATIENT'")
count_rule("CMP03", "Inpatient claims without a DRG", "fact_claim", "completeness", "WARN",
           "Inpatient claims with no DRG code (the placeholder OTH is counted separately in VAL10).",
           "dw.fact_claim", "drg_key IS NULL", "claim_type = 'INPATIENT'")
count_rule("CMP04", "Carrier lines with neither NPI nor HCPCS", "fact_claim_line", "completeness", "WARN",
           "Service lines kept for their dollars that carry no provider NPI and no procedure code.",
           "dw.fact_claim_line", "is_unidentified_line = 1")
count_rule("CMP05", "Members without a birth date", "dim_beneficiary", "completeness", "CRITICAL",
           "Every member needs a birth date for age-based reporting.",
           "dw.dim_beneficiary", "birth_date IS NULL")
count_rule("CMP06", "Institutional claims without a facility", "fact_claim", "completeness", "WARN",
           "Inpatient and outpatient claims with no facility (provider institution).",
           "dw.fact_claim", "facility_key IS NULL", "claim_type IN ('INPATIENT','OUTPATIENT')")

# ---------------- validity ----------------
count_rule("VAL01", "Discharge before admission", "fact_claim", "validity", "CRITICAL",
           "Inpatient claims where the discharge date precedes the admission date.",
           "dw.fact_claim", "discharge_date_key < admit_date_key",
           "claim_type = 'INPATIENT' AND admit_date_key IS NOT NULL AND discharge_date_key IS NOT NULL")
count_rule("VAL02", "Through-date before from-date", "fact_claim", "validity", "CRITICAL",
           "Claims whose end date is earlier than their start date.",
           "dw.fact_claim", "thru_date_key < from_date_key", "from_date_key IS NOT NULL AND thru_date_key IS NOT NULL")
count_rule("VAL03", "Claim through-date outside 2008-2010", "fact_claim", "validity", "WARN",
           "The CMS manual assigns a claim to the year of its through-date; dates outside 2008-2010 are unexpected.",
           "dw.fact_claim", "thru_date_key NOT BETWEEN 20080101 AND 20101231", "thru_date_key IS NOT NULL")
count_rule("VAL04", "Claims with a negative payment (adjustments)", "fact_claim", "validity", "INFO",
           "Claims with at least one negative payment segment or line; payment totals are net of these.",
           "dw.fact_claim", "is_adjustment = 1")
count_rule("VAL05", "Length of stay differs from utilization days", "fact_claim", "validity", "WARN",
           "Calendar days between admission and discharge versus the reported utilization day count.",
           "dw.fact_claim", "los_days <> utilization_days",
           "claim_type = 'INPATIENT' AND los_days IS NOT NULL AND utilization_days IS NOT NULL")
count_rule("VAL06", "Admission date differs from claim from-date", "fact_claim", "validity", "WARN",
           "Inpatient claims where the admission date and the claim start date disagree.",
           "dw.fact_claim", "admit_date_key <> from_date_key",
           "claim_type = 'INPATIENT' AND admit_date_key IS NOT NULL AND from_date_key IS NOT NULL")
count_rule("VAL07", "Implausible length of stay", "fact_claim", "validity", "WARN",
           "Inpatient stays shorter than 0 or longer than 365 days.",
           "dw.fact_claim", "los_days < 0 OR los_days > 365", "claim_type = 'INPATIENT' AND los_days IS NOT NULL")
count_rule("VAL08", "Death date before birth date", "dim_beneficiary", "validity", "CRITICAL",
           "Members whose death date precedes their birth date.",
           "dw.dim_beneficiary", "death_date < birth_date", "death_date IS NOT NULL AND birth_date IS NOT NULL")
count_rule("VAL09", "Implausible age (over 110 at end of 2010)", "dim_beneficiary", "validity", "WARN",
           "Members born before 1900-12-31.",
           "dw.dim_beneficiary", "birth_date < '19001231'", "birth_date IS NOT NULL")
rule("VAL10", "Placeholder DRG codes (OTH)", "fact_claim", "validity", "INFO",
     "Inpatient claims carrying the placeholder DRG OTH, excluded from DRG-level KPIs.",
     "SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN d.is_placeholder = 1 THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c LEFT JOIN dw.dim_drg d ON d.drg_key = c.drg_key WHERE c.claim_type = 'INPATIENT'")
count_rule("VAL11", "Placeholder NDC codes (OTHER)", "fact_rx_event", "validity", "INFO",
           "Prescription events carrying the placeholder NDC OTHER, excluded from drug-level KPIs.",
           "dw.fact_rx_event", "ndc_is_other = 1")
count_rule("VAL12", "Rx service date outside 2008-2010", "fact_rx_event", "validity", "WARN",
           "Prescription fills dated outside the 2008-2010 study window.",
           "dw.fact_rx_event", "service_date_key NOT BETWEEN 20080101 AND 20101231", "service_date_key IS NOT NULL")
count_rule("VAL13", "Coverage months above 12", "fact_member_year", "validity", "CRITICAL",
           "Member-years reporting more than 12 months of Part A, Part B, HMO or Part D coverage.",
           "dw.fact_member_year", "part_a_months > 12 OR part_b_months > 12 OR hmo_months > 12 OR part_d_months > 12")

# ---------------- consistency ----------------
rule("CON01", "Claims dated after the member's death", "fact_claim", "consistency", "WARN",
     "Claims whose start date is after the member's recorded death date.",
     "SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN b.death_date IS NOT NULL AND c.from_date_key > CONVERT(int, CONVERT(char(8), b.death_date, 112)) THEN 1 ELSE 0 END), 0) FROM dw.fact_claim c JOIN dw.dim_beneficiary b ON b.beneficiary_key = c.beneficiary_key WHERE c.from_date_key IS NOT NULL")
rule("CON02", "Prescription fills after the member's death", "fact_rx_event", "consistency", "WARN",
     "Part D fills dated after the member's recorded death date.",
     "SELECT @checked = COUNT_BIG(*), @failed = ISNULL(SUM(CASE WHEN b.death_date IS NOT NULL AND r.service_date_key > CONVERT(int, CONVERT(char(8), b.death_date, 112)) THEN 1 ELSE 0 END), 0) FROM dw.fact_rx_event r JOIN dw.dim_beneficiary b ON b.beneficiary_key = r.beneficiary_key WHERE r.service_date_key IS NOT NULL")

def q(s):
    return "N'" + s.replace("'", "''") + "'"

header = """USE PayerPulse;
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
"""

values = ",\n".join(
    f"('{r['id']}', {q(r['name'])}, '{r['layer']}', '{r['table']}', '{r['dim']}', '{r['sev']}', {q(r['desc'])},\n    {q(r['sql'])})"
    for r in RULES) + ";\nGO\n"

proc = """
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
"""

OUT_FILE.write_text(header + values + proc, encoding="utf-8")
print(f"Wrote {OUT_FILE} with {len(RULES)} rules")