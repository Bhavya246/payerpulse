from pathlib import Path

OUT_FILE = Path(__file__).resolve().parent.parent / "sql" / "12_dw_dimensions_part2.sql"

def rng(prefix, n):
    return [f"{prefix}{i}" for i in range(1, n + 1)]

def values(alias, cols):
    return ", ".join(f"({alias}.{c})" for c in cols)

# ---- sources of diagnosis codes (ICD-9-CM) ----
IP_DX  = ["admtng_icd9_dgns_cd"] + rng("icd9_dgns_cd_", 10)
OP_DX  = ["admtng_icd9_dgns_cd"] + rng("icd9_dgns_cd_", 10)
CAR_DX = rng("icd9_dgns_cd_", 8)

dx_sources = [
    ("stg.inpatient_claim",  IP_DX),
    ("stg.outpatient_claim", OP_DX),
    ("stg.carrier_claim",    CAR_DX),
]

# ---- sources of procedure codes ----
IP_PX   = rng("icd9_prcdr_cd_", 6)
OP_PX   = rng("icd9_prcdr_cd_", 6)
HCPCS45 = rng("hcpcs_cd_", 45)

px_sources = [
    ("ICD9-PCS", "stg.inpatient_claim",  IP_PX),
    ("ICD9-PCS", "stg.outpatient_claim", OP_PX),
    ("HCPCS",    "stg.inpatient_claim",  HCPCS45),
    ("HCPCS",    "stg.outpatient_claim", HCPCS45),
]

def timed_insert(dim_name, insert_sql):
    return (
f"DECLARE @t0 DATETIME2(0) = SYSUTCDATETIME(), @n BIGINT;\n"
f"IF NOT EXISTS (SELECT 1 FROM dw.{dim_name})\n"
f"BEGIN\n"
f"{insert_sql}\n"
f"    SET @n = @@ROWCOUNT;\n"
f"    INSERT INTO audit.load_log (pipeline_step, source_file, started_at, finished_at, rows_read, rows_loaded, status)\n"
f"    VALUES ('dw_dim_load', '{dim_name}', @t0, SYSUTCDATETIME(), @n, (SELECT COUNT_BIG(*) FROM dw.{dim_name}),\n"
f"            CASE WHEN @n = (SELECT COUNT_BIG(*) FROM dw.{dim_name}) THEN 'SUCCESS' ELSE 'FAILED' END);\n"
f"END\nGO\n")

out = ["USE PayerPulse;\nGO\n"]

# ================= dim_diagnosis =================
out.append(
"/* ---------- dim_diagnosis: every distinct ICD-9-CM diagnosis code seen on any claim ---------- */\n"
"IF OBJECT_ID(N'dw.dim_diagnosis', N'U') IS NULL\n"
"CREATE TABLE dw.dim_diagnosis (\n"
"    diagnosis_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_diagnosis PRIMARY KEY,\n"
"    icd9_code     VARCHAR(10)  NOT NULL CONSTRAINT UQ_dim_diagnosis_code UNIQUE,\n"
"    description   VARCHAR(300) NULL          -- filled later from a public ICD-9 reference if we add one\n"
");\nGO\n")
dx_parts = [f"        SELECT v.dx FROM {t} c CROSS APPLY (VALUES {values('c', cols)}) AS v(dx)" for t, cols in dx_sources]
dx_parts.append("        SELECT line_icd9_dgns_cd FROM stg.carrier_line")
dx_insert = ("    INSERT INTO dw.dim_diagnosis (icd9_code)\n"
             "    SELECT dx FROM (\n" + "\n        UNION\n".join(dx_parts) + "\n    ) t WHERE dx IS NOT NULL;")
out.append(timed_insert("dim_diagnosis", dx_insert))

# ================= dim_procedure =================
out.append(
"/* ---------- dim_procedure: ICD-9 procedure codes and HCPCS codes, kept apart by code_system ---------- */\n"
"IF OBJECT_ID(N'dw.dim_procedure', N'U') IS NULL\n"
"CREATE TABLE dw.dim_procedure (\n"
"    procedure_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_procedure PRIMARY KEY,\n"
"    code_system   VARCHAR(10)  NOT NULL,       -- 'ICD9-PCS' or 'HCPCS'\n"
"    code          VARCHAR(10)  NOT NULL,\n"
"    description   VARCHAR(300) NULL,\n"
"    CONSTRAINT UQ_dim_procedure UNIQUE (code_system, code),\n"
"    CONSTRAINT CK_dim_procedure_system CHECK (code_system IN ('ICD9-PCS','HCPCS'))\n"
");\nGO\n")
px_parts = [f"        SELECT '{sysname}' AS code_system, v.px AS code FROM {t} c CROSS APPLY (VALUES {values('c', cols)}) AS v(px)"
            for sysname, t, cols in px_sources]
px_parts.append("        SELECT 'HCPCS', hcpcs_cd FROM stg.carrier_line")
px_insert = ("    INSERT INTO dw.dim_procedure (code_system, code)\n"
             "    SELECT code_system, code FROM (\n" + "\n        UNION\n".join(px_parts) + "\n    ) t WHERE code IS NOT NULL;")
out.append(timed_insert("dim_procedure", px_insert))

# ================= coverage checks =================
checks = []
for t, cols in dx_sources:
    checks.append(
        f"SELECT 'diagnosis from {t}' AS check_name, COUNT(*) AS codes_missing_from_dim\n"
        f"FROM (SELECT DISTINCT v.dx FROM {t} c CROSS APPLY (VALUES {values('c', cols)}) AS v(dx) WHERE v.dx IS NOT NULL) s\n"
        f"LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL")
checks.append(
    "SELECT 'diagnosis from stg.carrier_line', COUNT(*)\n"
    "FROM (SELECT DISTINCT line_icd9_dgns_cd AS dx FROM stg.carrier_line WHERE line_icd9_dgns_cd IS NOT NULL) s\n"
    "LEFT JOIN dw.dim_diagnosis d ON d.icd9_code = s.dx WHERE d.diagnosis_key IS NULL")
for sysname, t, cols in px_sources:
    first = cols[0].rsplit("_", 1)[0]
    checks.append(
        f"SELECT '{sysname} from {t} ({first}_*)', COUNT(*)\n"
        f"FROM (SELECT DISTINCT v.px FROM {t} c CROSS APPLY (VALUES {values('c', cols)}) AS v(px) WHERE v.px IS NOT NULL) s\n"
        f"LEFT JOIN dw.dim_procedure p ON p.code_system = '{sysname}' AND p.code = s.px WHERE p.procedure_key IS NULL")
checks.append(
    "SELECT 'HCPCS from stg.carrier_line', COUNT(*)\n"
    "FROM (SELECT DISTINCT hcpcs_cd AS px FROM stg.carrier_line WHERE hcpcs_cd IS NOT NULL) s\n"
    "LEFT JOIN dw.dim_procedure p ON p.code_system = 'HCPCS' AND p.code = s.px WHERE p.procedure_key IS NULL")

out.append("-- Coverage check: every code used on any staged claim must exist in the dimension (all values must be 0)\n"
           + "\nUNION ALL\n".join(checks) + ";\n")

OUT_FILE.write_text("\n".join(out), encoding="utf-8")
print("Wrote", OUT_FILE)