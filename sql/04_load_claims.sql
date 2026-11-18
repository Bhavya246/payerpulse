USE PayerPulse;
GO
-- 1) Inpatient: expect 66,773 rows (seconds)
BULK INSERT [raw].v_inpatient_claims_file
FROM 'C:\payerpulse_data\DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);

-- 2) Outpatient: expect 790,790 rows (a minute or so)
BULK INSERT [raw].v_outpatient_claims_file
FROM 'C:\payerpulse_data\DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);

-- 3) Carrier part A: expect 2,370,667 rows (several minutes)
BULK INSERT [raw].v_carrier_claims_file
FROM 'C:\payerpulse_data\DE1_0_2008_to_2010_Carrier_Claims_Sample_1A.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);

-- 4) Carrier part B: expect 2,370,668 rows (several minutes). Same table: A and B are two halves of one dataset.
BULK INSERT [raw].v_carrier_claims_file
FROM 'C:\payerpulse_data\DE1_0_2008_to_2010_Carrier_Claims_Sample_1B.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);

-- 5) Part D prescription events: expect 5,552,421 rows (a few minutes)
BULK INSERT [raw].v_prescription_drug_events_file
FROM 'C:\payerpulse_data\DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_1.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', KEEPNULLS, TABLOCK);

SELECT 'inpatient' AS source, COUNT_BIG(*) AS loaded, 66773 AS expected FROM [raw].inpatient_claims
UNION ALL SELECT 'outpatient',  COUNT_BIG(*), 790790  FROM [raw].outpatient_claims
UNION ALL SELECT 'carrier A+B', COUNT_BIG(*), 4741335 FROM [raw].carrier_claims
UNION ALL SELECT 'pde',         COUNT_BIG(*), 5552421 FROM [raw].prescription_drug_events;

INSERT INTO audit.load_log (pipeline_step, source_file, finished_at, rows_read, rows_loaded, status)
SELECT 'raw_load', source, SYSUTCDATETIME(), expected, loaded,
       CASE WHEN loaded = expected THEN 'SUCCESS' ELSE 'FAILED' END
FROM (
    SELECT 'inpatient' AS source, COUNT_BIG(*) AS loaded, 66773 AS expected FROM [raw].inpatient_claims
    UNION ALL SELECT 'outpatient',  COUNT_BIG(*), 790790  FROM [raw].outpatient_claims
    UNION ALL SELECT 'carrier A+B', COUNT_BIG(*), 4741335 FROM [raw].carrier_claims
    UNION ALL SELECT 'pde',         COUNT_BIG(*), 5552421 FROM [raw].prescription_drug_events
) x;

SELECT * FROM audit.load_log ORDER BY load_id;