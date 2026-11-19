import csv
from pathlib import Path

DATA_DIR = Path(r"C:\payerpulse_data")
OUT_FILE = Path(__file__).resolve().parent.parent / "sql" / "07_stg_inpatient_outpatient.sql"

# staging table -> (raw table, CSV file to read the header from)
TABLES = {
    "inpatient_claim":  ("inpatient_claims",  "DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv"),
    "outpatient_claim": ("outpatient_claims", "DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv"),
}

DATE_COLS = {"clm_from_dt", "clm_thru_dt", "clm_admsn_dt", "nch_bene_dschrg_dt"}
AMT_COLS = {"clm_pmt_amt", "nch_prmry_pyr_clm_pd_amt", "clm_pass_thru_per_diem_amt",
            "nch_bene_ip_ddctbl_amt", "nch_bene_pta_coinsrnc_lblty_am",
            "nch_bene_blood_ddctbl_lblty_am", "nch_bene_ptb_ddctbl_amt", "nch_bene_ptb_coinsrnc_amt"}
SMALLINT_COLS = {"clm_utlztn_day_cnt"}

# derived flag columns: name -> expression computed from the raw text
FLAGS = {
    "inpatient_claim": [
        ("is_adjustment", "CASE WHEN TRY_CONVERT(decimal(12,2), clm_pmt_amt) < 0 THEN 1 ELSE 0 END"),
        ("drg_is_other",  "CASE WHEN clm_drg_cd = 'OTH' THEN 1 ELSE 0 END"),
    ],
    "outpatient_claim": [
        ("is_adjustment", "CASE WHEN TRY_CONVERT(decimal(12,2), clm_pmt_amt) < 0 THEN 1 ELSE 0 END"),
    ],
}

def col_type(c):
    if c == "desynpuf_id": return "VARCHAR(16) NOT NULL"
    if c == "clm_id":      return "VARCHAR(20) NOT NULL"
    if c == "segment":     return "TINYINT NOT NULL"
    if c in DATE_COLS:     return "DATE NULL"
    if c in AMT_COLS:      return "DECIMAL(12,2) NULL"
    if c in SMALLINT_COLS: return "SMALLINT NULL"
    return "VARCHAR(10) NULL"

def expr(c):
    if c == "segment":     return "TRY_CONVERT(tinyint, segment)"
    if c in DATE_COLS:     return f"TRY_CONVERT(date, {c}, 112)"
    if c in AMT_COLS:      return f"TRY_CONVERT(decimal(12,2), {c})"
    if c in SMALLINT_COLS: return f"TRY_CONVERT(smallint, {c})"
    return c

blocks = ["USE PayerPulse;\nGO\n"]
check_parts = []

for stg, (raw, csv_name) in TABLES.items():
    path = DATA_DIR / csv_name
    if not path.exists():
        print(f"SKIPPED {stg}: {path} not found")
        continue
    with open(path, newline="", encoding="utf-8") as f:
        cols = [c.strip().lower() for c in next(csv.reader(f))]
    flags = FLAGS[stg]
    print(f"{stg}: {len(cols)} source columns + {len(flags)} flag columns")

    ddl_cols = [f"{c} {col_type(c)}" for c in cols] + [f"{n} BIT NOT NULL" for n, _ in flags]
    ins_cols = cols + [n for n, _ in flags]
    sel_cols = [expr(c) for c in cols] + [e for _, e in flags]

    blocks.append(f"""IF OBJECT_ID(N'stg.{stg}', N'U') IS NOT NULL DROP TABLE stg.{stg};
GO
CREATE TABLE stg.{stg} (
    {(","+chr(10)+"    ").join(ddl_cols)},
    CONSTRAINT PK_stg_{stg} PRIMARY KEY (clm_id, segment)
);
GO
DECLARE @load_id INT, @raw_rows BIGINT, @loaded BIGINT;
SELECT @raw_rows = COUNT_BIG(*) FROM raw.{raw};
INSERT INTO audit.load_log (pipeline_step, source_file, rows_read)
VALUES ('stg_load', 'raw.{raw} -> stg.{stg}', @raw_rows);
SET @load_id = SCOPE_IDENTITY();

INSERT INTO stg.{stg} (
    {(","+chr(10)+"    ").join(ins_cols)}
)
SELECT
    {(","+chr(10)+"    ").join(sel_cols)}
FROM raw.{raw};
SET @loaded = @@ROWCOUNT;

UPDATE audit.load_log
SET finished_at = SYSUTCDATETIME(), rows_loaded = @loaded,
    status = CASE WHEN @loaded = @raw_rows THEN 'SUCCESS' ELSE 'FAILED' END
WHERE load_id = @load_id;
GO
""")

    for c in cols:
        if c in DATE_COLS or c in AMT_COLS or c in SMALLINT_COLS or c == "segment":
            check_parts.append(
                f"SELECT '{stg}' AS tbl, '{c}' AS col, "
                f"(SELECT COUNT({c}) FROM raw.{raw}) AS raw_non_null, "
                f"(SELECT COUNT({c}) FROM stg.{stg}) AS stg_non_null")

blocks.append("-- Conversion check: any row where raw_non_null <> stg_non_null lost a value in conversion\n"
              + "\nUNION ALL\n".join(check_parts) + "\nORDER BY 1, 2;\n")

OUT_FILE.write_text("\n".join(blocks), encoding="utf-8")
print("Wrote", OUT_FILE)