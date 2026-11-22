GO

/* ---------- keys and constraints (added after the load) ---------- */
ALTER TABLE dw.fact_claim ADD CONSTRAINT PK_fact_claim PRIMARY KEY CLUSTERED (claim_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT UQ_fact_claim_source UNIQUE (claim_type, claim_id);
ALTER TABLE dw.fact_claim ADD CONSTRAINT CK_fact_claim_type CHECK (claim_type IN ('INPATIENT','OUTPATIENT','CARRIER'));
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_beneficiary FOREIGN KEY (beneficiary_key)    REFERENCES dw.dim_beneficiary(beneficiary_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_from_date   FOREIGN KEY (from_date_key)      REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_thru_date   FOREIGN KEY (thru_date_key)      REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_admit_date  FOREIGN KEY (admit_date_key)     REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_disch_date  FOREIGN KEY (discharge_date_key) REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_facility    FOREIGN KEY (facility_key)       REFERENCES dw.dim_provider(provider_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_attending   FOREIGN KEY (attending_npi_key)  REFERENCES dw.dim_provider(provider_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_operating   FOREIGN KEY (operating_npi_key)  REFERENCES dw.dim_provider(provider_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_drg         FOREIGN KEY (drg_key)            REFERENCES dw.dim_drg(drg_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_admit_dx    FOREIGN KEY (admitting_dx_key)   REFERENCES dw.dim_diagnosis(diagnosis_key);
ALTER TABLE dw.fact_claim ADD CONSTRAINT FK_fc_principal_dx FOREIGN KEY (principal_dx_key)  REFERENCES dw.dim_diagnosis(diagnosis_key);
GO

-- 1) Claim counts (expect 66,705 / 779,815 / 4,741,335)
SELECT 'INPATIENT' AS claim_type, COUNT(*) AS in_fact, (SELECT COUNT(DISTINCT clm_id) FROM stg.inpatient_claim) AS expected
FROM dw.fact_claim WHERE claim_type = 'INPATIENT'
UNION ALL SELECT 'OUTPATIENT', COUNT(*), (SELECT COUNT(DISTINCT clm_id) FROM stg.outpatient_claim) FROM dw.fact_claim WHERE claim_type = 'OUTPATIENT'
UNION ALL SELECT 'CARRIER', COUNT(*), (SELECT COUNT_BIG(*) FROM stg.carrier_claim) FROM dw.fact_claim WHERE claim_type = 'CARRIER';

-- 2) Dollars must match exactly
SELECT 'inpatient: Medicare paid' AS check_name, (SELECT SUM(clm_pmt_amt) FROM stg.inpatient_claim) AS staging,
       (SELECT SUM(medicare_paid_amt) FROM dw.fact_claim WHERE claim_type = 'INPATIENT') AS warehouse
UNION ALL SELECT 'outpatient: Medicare paid', (SELECT SUM(clm_pmt_amt) FROM stg.outpatient_claim),
       (SELECT SUM(medicare_paid_amt) FROM dw.fact_claim WHERE claim_type = 'OUTPATIENT')
UNION ALL SELECT 'carrier: Medicare paid', (SELECT SUM(line_nch_pmt_amt) FROM stg.carrier_line),
       (SELECT SUM(medicare_paid_amt) FROM dw.fact_claim WHERE claim_type = 'CARRIER')
UNION ALL SELECT 'inpatient: primary payer', (SELECT SUM(nch_prmry_pyr_clm_pd_amt) FROM stg.inpatient_claim),
       (SELECT SUM(primary_payer_paid_amt) FROM dw.fact_claim WHERE claim_type = 'INPATIENT')
UNION ALL SELECT 'outpatient: primary payer', (SELECT SUM(nch_prmry_pyr_clm_pd_amt) FROM stg.outpatient_claim),
       (SELECT SUM(primary_payer_paid_amt) FROM dw.fact_claim WHERE claim_type = 'OUTPATIENT')
UNION ALL SELECT 'carrier: primary payer', (SELECT SUM(line_bene_prmry_pyr_pd_amt) FROM stg.carrier_line),
       (SELECT SUM(primary_payer_paid_amt) FROM dw.fact_claim WHERE claim_type = 'CARRIER');

-- 3) Flags
SELECT claim_type, SUM(CAST(is_adjustment AS int)) AS adjustment_claims,
       SUM(CAST(is_orphan_segment AS int)) AS orphan_segment_claims,
       SUM(CASE WHEN segment_count > 1 THEN 1 ELSE 0 END) AS multi_segment_claims,
       SUM(CASE WHEN from_date_key IS NULL THEN 1 ELSE 0 END) AS no_dates
FROM dw.fact_claim GROUP BY claim_type;

-- 4) First look at admissions and the audit row
SELECT COUNT(*) AS admissions, AVG(CAST(los_days AS float)) AS avg_los_days FROM dw.fact_claim WHERE claim_type = 'INPATIENT';
SELECT TOP 2 * FROM audit.load_log ORDER BY load_id DESC;

-- File sizes for the project database and tempdb
SELECT DB_NAME(database_id) AS db, name, type_desc, CAST(size * 8 / 1024.0 / 1024 AS decimal(10,2)) AS size_gb
FROM sys.master_files
WHERE database_id IN (DB_ID('PayerPulse'), 2)
ORDER BY db, type_desc;

USE PayerPulse;
-- How much of the data file is actually in use?
SELECT name, CAST(size * 8 / 1024.0 / 1024 AS decimal(10,2)) AS size_gb,
       CAST(FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024.0 / 1024 AS decimal(10,2)) AS used_gb
FROM sys.database_files;

-- The biggest tables
SELECT TOP 10 s.name + '.' + t.name AS table_name,
       CAST(SUM(ps.used_page_count) * 8 / 1024.0 / 1024 AS decimal(10,2)) AS used_gb,
       SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.row_count END) AS row_count
FROM sys.dm_db_partition_stats ps
JOIN sys.tables t ON t.object_id = ps.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
GROUP BY s.name, t.name ORDER BY used_gb DESC;

-- Confirm fact_claim is fully keyed (expect 11) and the audit row is SUCCESS
SELECT COUNT(*) AS foreign_keys FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dw.fact_claim');
SELECT TOP 2 * FROM audit.load_log ORDER BY load_id DESC;

USE PayerPulse;
EXEC sp_estimate_data_compression_savings 'raw', 'carrier_claims', NULL, NULL, 'PAGE';

ALTER TABLE raw.carrier_claims REBUILD WITH (DATA_COMPRESSION = PAGE);

USE PayerPulse;
SELECT name, CAST(size * 8 / 1024.0 / 1024 AS decimal(10,2)) AS size_gb,
       CAST(FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024.0 / 1024 AS decimal(10,2)) AS used_gb
FROM sys.database_files;

ALTER TABLE stg.carrier_line  REBUILD WITH (DATA_COMPRESSION = PAGE);
ALTER TABLE stg.pde_event     REBUILD WITH (DATA_COMPRESSION = PAGE);
ALTER TABLE stg.carrier_claim REBUILD WITH (DATA_COMPRESSION = PAGE);

USE PayerPulse;

-- Which raw/staging tables are compressed right now?
SELECT s.name + '.' + t.name AS table_name, p.data_compression_desc, SUM(p.rows) AS row_count
FROM sys.partitions p
JOIN sys.tables t ON t.object_id = p.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE p.index_id IN (0, 1) AND s.name IN ('raw', 'stg')
GROUP BY s.name, t.name, p.data_compression_desc
ORDER BY 1;

-- Memory: SQL Server's limits, the machine's RAM, and what SQL Server is using
SELECT name, value_in_use FROM sys.configurations WHERE name IN ('max server memory (MB)', 'min server memory (MB)');
SELECT total_physical_memory_kb / 1024 AS total_ram_mb, available_physical_memory_kb / 1024 AS available_ram_mb FROM sys.dm_os_sys_memory;
SELECT physical_memory_in_use_kb / 1024 AS sql_memory_in_use_mb FROM sys.dm_os_process_memory;

-- fact_claim fully keyed (expect 11) and the audit rows
SELECT COUNT(*) AS foreign_keys FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dw.fact_claim');
SELECT TOP 2 * FROM audit.load_log ORDER BY load_id DESC;