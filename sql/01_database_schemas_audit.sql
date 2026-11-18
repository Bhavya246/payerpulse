CREATE DATABASE PayerPulse;
GO

SELECT DB_NAME() AS CurrentDatabase;

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'raw'
)
BEGIN
    EXEC('CREATE SCHEMA raw');
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
BEGIN
    EXEC('CREATE SCHEMA stg');
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dw')
BEGIN
    EXEC('CREATE SCHEMA dw');
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
BEGIN
    EXEC('CREATE SCHEMA audit');
END;
GO

IF OBJECT_ID(N'audit.load_log', N'U') IS NULL
    CREATE TABLE audit.load_log (
        load_id       INT             IDENTITY (1, 1) PRIMARY KEY,
        pipeline_step VARCHAR (100)   NOT NULL,
        source_file   NVARCHAR (260)  NULL,
        started_at    DATETIME2 (0)   DEFAULT SYSUTCDATETIME() NOT NULL,
        finished_at   DATETIME2 (0)   NULL,
        rows_read     BIGINT          NULL,
        rows_loaded   BIGINT          NULL,
        status        VARCHAR (12)    DEFAULT 'RUNNING' NOT NULL,
        error_message NVARCHAR (2000) NULL
    );


GO