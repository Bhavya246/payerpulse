USE PayerPulse;
GO
CREATE TABLE [raw].beneficiary_summary (
    desynpuf_id VARCHAR(50), bene_birth_dt VARCHAR(50), bene_death_dt VARCHAR(50),
    bene_sex_ident_cd VARCHAR(50), bene_race_cd VARCHAR(50), bene_esrd_ind VARCHAR(50),
    sp_state_code VARCHAR(50), bene_county_cd VARCHAR(50),
    bene_hi_cvrage_tot_mons VARCHAR(50), bene_smi_cvrage_tot_mons VARCHAR(50),
    bene_hmo_cvrage_tot_mons VARCHAR(50), plan_cvrg_mos_num VARCHAR(50),
    sp_alzhdmta VARCHAR(50), sp_chf VARCHAR(50), sp_chrnkidn VARCHAR(50), sp_cncr VARCHAR(50),
    sp_copd VARCHAR(50), sp_depressn VARCHAR(50), sp_diabetes VARCHAR(50), sp_ischmcht VARCHAR(50),
    sp_osteoprs VARCHAR(50), sp_ra_oa VARCHAR(50), sp_strketia VARCHAR(50),
    medreimb_ip VARCHAR(50), benres_ip VARCHAR(50), pppymt_ip VARCHAR(50),
    medreimb_op VARCHAR(50), benres_op VARCHAR(50), pppymt_op VARCHAR(50),
    medreimb_car VARCHAR(50), benres_car VARCHAR(50), pppymt_car VARCHAR(50),
    file_year SMALLINT NULL,
    loaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE VIEW [raw].v_beneficiary_summary_file AS
SELECT desynpuf_id, bene_birth_dt, bene_death_dt, bene_sex_ident_cd, bene_race_cd, bene_esrd_ind,
       sp_state_code, bene_county_cd, bene_hi_cvrage_tot_mons, bene_smi_cvrage_tot_mons,
       bene_hmo_cvrage_tot_mons, plan_cvrg_mos_num, sp_alzhdmta, sp_chf, sp_chrnkidn, sp_cncr,
       sp_copd, sp_depressn, sp_diabetes, sp_ischmcht, sp_osteoprs, sp_ra_oa, sp_strketia,
       medreimb_ip, benres_ip, pppymt_ip, medreimb_op, benres_op, pppymt_op,
       medreimb_car, benres_car, pppymt_car
FROM [raw].beneficiary_summary;
GO

BULK INSERT [raw].v_beneficiary_summary_file
FROM 'C:\payerpulse_data\DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);
UPDATE [raw].beneficiary_summary SET file_year = 2008 WHERE file_year IS NULL;

BULK INSERT [raw].v_beneficiary_summary_file
FROM 'C:\payerpulse_data\DE1_0_2009_Beneficiary_Summary_File_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);
UPDATE [raw].beneficiary_summary SET file_year = 2009 WHERE file_year IS NULL;

BULK INSERT [raw].v_beneficiary_summary_file
FROM 'C:\payerpulse_data\DE1_0_2010_Beneficiary_Summary_File_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);
UPDATE [raw].beneficiary_summary SET file_year = 2010 WHERE file_year IS NULL;
GO

SELECT file_year, COUNT(*) AS loaded
FROM [raw].beneficiary_summary GROUP BY file_year ORDER BY file_year;

SELECT TOP 5 * FROM [raw].beneficiary_summary WHERE file_year = 2008;

SELECT
    COUNT(*)                                             AS total_rows,
    SUM(CASE WHEN bene_death_dt IS NULL THEN 1 ELSE 0 END) AS death_date_is_null,
    SUM(CASE WHEN bene_death_dt = ''    THEN 1 ELSE 0 END) AS death_date_is_blank_text
FROM [raw].beneficiary_summary;

INSERT INTO audit.load_log (pipeline_step, source_file, finished_at, rows_read, rows_loaded, status)
SELECT 'raw_load', source, SYSUTCDATETIME(), expected, loaded,
       CASE WHEN loaded = expected THEN 'SUCCESS' ELSE 'FAILED' END
FROM (
    SELECT 'beneficiary 2008' AS source, COUNT_BIG(*) AS loaded, 116352 AS expected FROM [raw].beneficiary_summary WHERE file_year = 2008
    UNION ALL SELECT 'beneficiary 2009', COUNT_BIG(*), 114538 FROM [raw].beneficiary_summary WHERE file_year = 2009
    UNION ALL SELECT 'beneficiary 2010', COUNT_BIG(*), 112754 FROM [raw].beneficiary_summary WHERE file_year = 2010
) x;

SELECT * FROM audit.load_log ORDER BY load_id;