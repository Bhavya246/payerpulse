import csv
from pathlib import Path

DATA_DIR = Path(r"C:\payerpulse_data")
OUT_FILE = Path(__file__).resolve().parent.parent / "sql" / "03_raw_tables.sql"

TABLES = {
    "inpatient_claims":         ("DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv", 81),
    "outpatient_claims":        ("DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv", 76),
    "carrier_claims":           ("DE1_0_2008_to_2010_Carrier_Claims_Sample_1A.csv", 142),
    "prescription_drug_events": ("DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_1.csv", 8),
}

blocks = ["USE PayerPulse;\nGO\n"]
for table, (filename, expected) in TABLES.items():
    path = DATA_DIR / filename
    if not path.exists():
        print(f"SKIPPED {table}: {path} not found")
        continue
    with open(path, newline="", encoding="utf-8") as f:
        cols = [c.strip().lower() for c in next(csv.reader(f))]
    flag = "OK" if len(cols) == expected else f"WARNING expected {expected}"
    print(f"{table}: {len(cols)} columns ({flag})")
    col_defs = ",\n    ".join(f"{c} VARCHAR(50) NULL" for c in cols)
    col_list = ", ".join(cols)
    blocks.append(f"""CREATE TABLE [raw].[{table}] (
    {col_defs},
    loaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE VIEW [raw].[v_{table}_file] AS
SELECT {col_list} FROM [raw].[{table}];
GO
""")

OUT_FILE.write_text("\n".join(blocks), encoding="utf-8")
print("Wrote", OUT_FILE)