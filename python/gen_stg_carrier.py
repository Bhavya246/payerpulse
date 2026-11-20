from pathlib import Path

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"
N = 13  # service-line slots per carrier claim

# (staging column, raw column prefix, SQL type)
LINE_FIELDS = [
    ("prf_physn_npi",              "prf_physn_npi_",              "VARCHAR(10)"),
    ("tax_num",                    "tax_num_",                    "VARCHAR(10)"),
    ("hcpcs_cd",                   "hcpcs_cd_",                   "VARCHAR(10)"),
    ("line_nch_pmt_amt",           "line_nch_pmt_amt_",           "DECIMAL(12,2)"),
    ("line_bene_ptb_ddctbl_amt",   "line_bene_ptb_ddctbl_amt_",   "DECIMAL(12,2)"),
    ("line_bene_prmry_pyr_pd_amt", "line_bene_prmry_pyr_pd_amt_", "DECIMAL(12,2)"),
    ("line_coinsrnc_amt",          "line_coinsrnc_amt_",          "DECIMAL(12,2)"),
    ("line_alowd_chrg_amt",        "line_alowd_chrg_amt_",        "DECIMAL(12,2)"),
    ("line_prcsg_ind_cd",          "line_prcsg_ind_cd_",          "VARCHAR(5)"),
    ("line_icd9_dgns_cd",          "line_icd9_dgns_cd_",          "VARCHAR(10)"),
]
# A slot is a REAL service line only if one of these identifying fields is present.
# (Amount columns are filled with 0.00 in empty slots, so they cannot be used to detect a line.)
KEY_FIELDS = ["prf_physn_npi", "hcpcs_cd"]

dx_cols = [f"icd9_dgns_cd_{i}" for i in range(1, 9)]

# ===================== 09: carrier claim header =====================
claim_ddl_dx = ",\n    ".join(f"{c} VARCHAR(10) NULL" for c in dx_cols)
claim_sql = (
"USE PayerPulse;\nGO\n\n"
"IF OBJECT_ID(N'stg.carrier_claim', N'U') IS NOT NULL DROP TABLE stg.carrier_claim;\n"
"GO\n"
"CREATE TABLE stg.carrier_claim (\n"
"    clm_id      VARCHAR(20) NOT NULL,\n"
"    desynpuf_id VARCHAR(16) NOT NULL,\n"
"    from_date   DATE NULL,\n"
"    thru_date   DATE NULL,\n"
"    " + claim_ddl_dx + ",\n"
"    CONSTRAINT PK_stg_carrier_claim PRIMARY KEY (clm_id)\n"
");\n"
"GO\n"
"DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;\n"
"SELECT @raw_rows = COUNT_BIG(*) FROM raw.carrier_claims;\n"
"INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)\n"
"VALUES ('stg_load', 'raw.carrier_claims -> stg.carrier_claim', @raw_rows);\n"
"SET @load_id = SCOPE_IDENTITY();\n\n"
"INSERT INTO stg.carrier_claim (clm_id, desynpuf_id, from_date, thru_date, " + ", ".join(dx_cols) + ")\n"
"SELECT clm_id, desynpuf_id, TRY_CONVERT(date, clm_from_dt, 112), TRY_CONVERT(date, clm_thru_dt, 112), "
+ ", ".join(dx_cols) + "\n"
"FROM raw.carrier_claims;\n"
"SET @loaded = @@ROWCOUNT;\n\n"
"UPDATE audit.load_log\n"
"SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,\n"
"    status = CASE WHEN @loaded = @raw_rows THEN 'SUCCESS' ELSE 'FAILED' END\n"
"WHERE load_id = @load_id;\n"
"GO\n\n"
"-- Conversion check: raw_non_null must equal stg_non_null on every row\n"
"SELECT 'claim rows' AS col, (SELECT COUNT_BIG(*) FROM raw.carrier_claims) AS raw_non_null, (SELECT COUNT_BIG(*) FROM stg.carrier_claim) AS stg_non_null\n"
"UNION ALL SELECT 'clm_from_dt', (SELECT COUNT_BIG(clm_from_dt) FROM raw.carrier_claims), (SELECT COUNT_BIG(from_date) FROM stg.carrier_claim)\n"
"UNION ALL SELECT 'clm_thru_dt', (SELECT COUNT_BIG(clm_thru_dt) FROM raw.carrier_claims), (SELECT COUNT_BIG(thru_date) FROM stg.carrier_claim);\n"
)

# ===================== 10: carrier service lines =====================
line_ddl = ",\n    ".join(f"{name} {typ} NULL" for name, _, typ in LINE_FIELDS)
values_rows = []
for n in range(1, N + 1):
    vals = [str(n)] + [f"c.{prefix}{n}" for _, prefix, _ in LINE_FIELDS]
    values_rows.append("        (" + ", ".join(vals) + ")")
values_sql = ",\n".join(values_rows)
v_aliases = ", ".join(["n"] + [f"c{i}" for i in range(1, len(LINE_FIELDS) + 1)])
select_exprs = []
for i, (_, _, typ) in enumerate(LINE_FIELDS, 1):
    select_exprs.append(f"TRY_CONVERT(decimal(12,2), v.c{i})" if typ.startswith("DECIMAL") else f"v.c{i}")
names = [n for n, _, _ in LINE_FIELDS]
key_idx = [names.index(k) + 1 for k in KEY_FIELDS]
where_any = "\n   OR ".join(f"v.c{i} IS NOT NULL" for i in key_idx)
ins_cols = ", ".join(["clm_id", "line_number"] + names)

def raw_slot_count():
    terms = []
    for n in range(1, N + 1):
        cond = " OR ".join(f"{dict((a, b) for a, b, _ in LINE_FIELDS)[k]}{n} IS NOT NULL" for k in KEY_FIELDS)
        terms.append(f"SUM(CASE WHEN {cond} THEN 1 ELSE 0 END)")
    return " + ".join(terms)

def raw_money(prefix):
    return " + ".join(f"ISNULL(SUM(TRY_CONVERT(decimal(18,2), {prefix}{n})), 0)" for n in range(1, N + 1))

line_sql = (
"USE PayerPulse;\nGO\n\n"
"-- Make sure the log is cheap: SIMPLE recovery + a heap loaded WITH (TABLOCK) is minimally logged.\n"
"ALTER DATABASE PayerPulse SET RECOVERY SIMPLE;\nGO\n\n"
"IF OBJECT_ID(N'stg.carrier_line', N'U') IS NOT NULL DROP TABLE stg.carrier_line;\n"
"GO\n"
"-- No primary key yet: the key is added AFTER the load so the insert can be minimally logged.\n"
"CREATE TABLE stg.carrier_line (\n"
"    clm_id      VARCHAR(20) NOT NULL,\n"
"    line_number TINYINT     NOT NULL,\n"
"    " + line_ddl + "\n"
");\n"
"GO\n"
"DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;\n"
"SELECT @raw_rows = COUNT_BIG(*) FROM raw.carrier_claims;\n"
"INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)\n"
"VALUES ('stg_load', 'raw.carrier_claims -> stg.carrier_line (unpivot)', @raw_rows);\n"
"SET @load_id = SCOPE_IDENTITY();\n\n"
"-- A slot is a real line only if " + " or ".join(KEY_FIELDS) + " is present.\n"
"INSERT INTO stg.carrier_line WITH (TABLOCK) (" + ins_cols + ")\n"
"SELECT c.clm_id, v.n,\n       " + ",\n       ".join(select_exprs) + "\n"
"FROM raw.carrier_claims c\n"
"CROSS APPLY (VALUES\n" + values_sql + "\n"
") AS v(" + v_aliases + ")\n"
"WHERE " + where_any + ";\n"
"SET @loaded = @@ROWCOUNT;\n\n"
"ALTER TABLE stg.carrier_line ADD CONSTRAINT PK_stg_carrier_line PRIMARY KEY CLUSTERED (clm_id, line_number);\n\n"
"-- rows_read = carrier CLAIMS read; rows_loaded = service LINES produced.\n"
"UPDATE audit.load_log\n"
"SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,\n"
"    status = CASE WHEN @loaded > 0 THEN 'SUCCESS' ELSE 'FAILED' END\n"
"WHERE load_id = @load_id;\n"
"GO\n\n"
"-- Reconciliation. Counts: line slots with a real key in raw vs rows in staging.\n"
"-- Dollars: the sum over all 13 slots in raw must equal the staging total (no money dropped with empty slots).\n"
"SELECT 'real line slots' AS check_name,\n"
"       (SELECT " + raw_slot_count() + " FROM raw.carrier_claims) AS raw_value,\n"
"       (SELECT COUNT_BIG(*) FROM stg.carrier_line) AS stg_value\n"
"UNION ALL SELECT 'line_nch_pmt_amt total',\n"
"       (SELECT " + raw_money("line_nch_pmt_amt_") + " FROM raw.carrier_claims),\n"
"       (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line)\n"
"UNION ALL SELECT 'line_alowd_chrg_amt total',\n"
"       (SELECT " + raw_money("line_alowd_chrg_amt_") + " FROM raw.carrier_claims),\n"
"       (SELECT SUM(line_alowd_chrg_amt) FROM stg.carrier_line);\n"
)

(SQL_DIR / "09_stg_carrier_claim.sql").write_text(claim_sql, encoding="utf-8")
(SQL_DIR / "10_stg_carrier_line.sql").write_text(line_sql, encoding="utf-8")
print("Wrote 09_stg_carrier_claim.sql and 10_stg_carrier_line.sql in", SQL_DIR)