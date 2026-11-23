-- ============================================================================
-- SCRIPT 01: Medicare Advantage PHM Database & Relational Schema (DDL)
-- Target Engine: Microsoft SQL Server (T-SQL)
-- Data Source: Synthea Synthetic US Patient Records (CSV)
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MedicareAdvantage_PHM')
BEGIN
    CREATE DATABASE MedicareAdvantage_PHM;
END;
GO

USE MedicareAdvantage_PHM;
GO

-- 1. Configuration Table (Avoids hardcoded Measurement Years in Views/Power BI)
IF OBJECT_ID('dbo.phm_config', 'U') IS NOT NULL DROP TABLE dbo.phm_config;
CREATE TABLE dbo.phm_config (
    ConfigID        INT PRIMARY KEY CHECK (ConfigID = 1),
    MeasurementYear INT NOT NULL
);
-- Default placeholder; auto-updated after CSV import in Script 04
INSERT INTO dbo.phm_config (ConfigID, MeasurementYear) VALUES (1, 2021);
GO

-- 2. Providers Dimension Table (providers.csv)
IF OBJECT_ID('dbo.providers', 'U') IS NOT NULL DROP TABLE dbo.providers;
CREATE TABLE dbo.providers (
    Id              VARCHAR(50)   NOT NULL PRIMARY KEY,
    ORGANIZATION    VARCHAR(50)   NULL,
    [NAME]          VARCHAR(150)  NULL,
    GENDER          VARCHAR(10)   NULL,
    SPECIALITY      VARCHAR(150)  NULL,
    [ADDRESS]       VARCHAR(200)  NULL,
    CITY            VARCHAR(100)  NULL,
    [STATE]         VARCHAR(50)   NULL,
    ZIP             VARCHAR(20)   NULL,
    LAT             DECIMAL(10,6) NULL,
    LON             DECIMAL(10,6) NULL,
    UTILIZATION     INT           NULL
);
GO

-- 3. Patients / Members Dimension Table (patients.csv)
IF OBJECT_ID('dbo.patients', 'U') IS NOT NULL DROP TABLE dbo.patients;
CREATE TABLE dbo.patients (
    Id                  VARCHAR(50)   NOT NULL PRIMARY KEY,
    BIRTHDATE           DATE          NOT NULL,
    DEATHDATE           DATE          NULL,
    SSN                 VARCHAR(20)   NULL,
    DRIVERS             VARCHAR(50)   NULL,
    PASSPORT            VARCHAR(50)   NULL,
    PREFIX              VARCHAR(20)   NULL,
    [FIRST]             VARCHAR(100)  NULL,
    [LAST]              VARCHAR(100)  NULL,
    SUFFIX              VARCHAR(20)   NULL,
    MAIDEN              VARCHAR(100)  NULL,
    MARITAL             VARCHAR(10)   NULL,
    RACE                VARCHAR(50)   NULL,
    ETHNICITY           VARCHAR(50)   NULL,
    GENDER              VARCHAR(10)   NULL,
    BIRTHPLACE          VARCHAR(200)  NULL,
    [ADDRESS]           VARCHAR(200)  NULL,
    CITY                VARCHAR(100)  NULL,
    [STATE]             VARCHAR(50)   NULL,
    COUNTY              VARCHAR(100)  NULL,
    ZIP                 VARCHAR(20)   NULL,
    LAT                 DECIMAL(10,6) NULL,
    LON                 DECIMAL(10,6) NULL,
    HEALTHCARE_EXPENSES DECIMAL(14,2) NULL,
    HEALTHCARE_COVERAGE DECIMAL(14,2) NULL,
    INCOME              DECIMAL(14,2) NULL
);
GO

-- 4. Encounters / Claims Fact Table (encounters.csv)
IF OBJECT_ID('dbo.encounters', 'U') IS NOT NULL DROP TABLE dbo.encounters;
CREATE TABLE dbo.encounters (
    Id                  VARCHAR(50)    NOT NULL PRIMARY KEY,
    [START]             DATETIMEOFFSET NOT NULL,
    [STOP]              DATETIMEOFFSET NULL,
    PATIENT             VARCHAR(50)    NOT NULL,
    ORGANIZATION        VARCHAR(50)    NULL,
    PROVIDER            VARCHAR(50)    NULL,
    PAYER               VARCHAR(50)    NULL,
    ENCOUNTERCLASS      VARCHAR(50)    NULL, -- ambulatory, emergency, inpatient, wellness
    CODE                VARCHAR(50)    NULL,
    [DESCRIPTION]       VARCHAR(300)   NULL,
    BASE_ENCOUNTER_COST DECIMAL(12,2)  NULL,
    TOTAL_CLAIM_COST    DECIMAL(12,2)  NULL,
    PAYER_COVERAGE      DECIMAL(12,2)  NULL,
    REASONCODE          VARCHAR(50)    NULL,
    REASONDESCRIPTION   VARCHAR(300)   NULL,
    CONSTRAINT FK_Encounters_Patient  FOREIGN KEY (PATIENT)  REFERENCES dbo.patients(Id),
    CONSTRAINT FK_Encounters_Provider FOREIGN KEY (PROVIDER) REFERENCES dbo.providers(Id)
);
GO

-- 5. Conditions / Diagnoses Table (conditions.csv)
IF OBJECT_ID('dbo.conditions', 'U') IS NOT NULL DROP TABLE dbo.conditions;
CREATE TABLE dbo.conditions (
    ConditionRowID  BIGINT IDENTITY(1,1) PRIMARY KEY,
    [START]         DATE          NOT NULL,
    [STOP]          DATE          NULL,
    PATIENT         VARCHAR(50)   NOT NULL,
    ENCOUNTER       VARCHAR(50)   NULL,
    CODE            VARCHAR(50)   NOT NULL, -- SNOMED-CT
    [DESCRIPTION]   VARCHAR(300)  NULL,
    CONSTRAINT FK_Conditions_Patient   FOREIGN KEY (PATIENT)   REFERENCES dbo.patients(Id),
    CONSTRAINT FK_Conditions_Encounter FOREIGN KEY (ENCOUNTER) REFERENCES dbo.encounters(Id)
);
GO

-- 6. Observations / Clinical Labs & Vitals Table (observations.csv)
IF OBJECT_ID('dbo.observations', 'U') IS NOT NULL DROP TABLE dbo.observations;
CREATE TABLE dbo.observations (
    ObservationRowID BIGINT IDENTITY(1,1) PRIMARY KEY,
    [DATE]           DATETIMEOFFSET NOT NULL,
    PATIENT          VARCHAR(50)    NOT NULL,
    ENCOUNTER        VARCHAR(50)    NULL,
    CODE             VARCHAR(50)    NOT NULL, -- LOINC
    [DESCRIPTION]    VARCHAR(300)   NULL,
    [VALUE]          VARCHAR(200)   NULL,
    UNITS            VARCHAR(50)    NULL,
    [TYPE]           VARCHAR(50)    NULL,
    CONSTRAINT FK_Observations_Patient FOREIGN KEY (PATIENT) REFERENCES dbo.patients(Id)
);
GO

-- 7. Medications Table (medications.csv)
IF OBJECT_ID('dbo.medications', 'U') IS NOT NULL DROP TABLE dbo.medications;
CREATE TABLE dbo.medications (
    MedicationRowID   BIGINT IDENTITY(1,1) PRIMARY KEY,
    [START]           DATETIMEOFFSET NOT NULL,
    [STOP]            DATETIMEOFFSET NULL,
    PATIENT           VARCHAR(50)    NOT NULL,
    PAYER             VARCHAR(50)    NULL,
    ENCOUNTER         VARCHAR(50)    NULL,
    CODE              VARCHAR(50)    NOT NULL, -- RxNorm
    [DESCRIPTION]     VARCHAR(300)   NULL,
    BASE_COST         DECIMAL(12,2)  NULL,
    PAYER_COVERAGE    DECIMAL(12,2)  NULL,
    DISPENSES         INT            NULL,
    TOTALCOST         DECIMAL(12,2)  NULL,
    REASONCODE        VARCHAR(50)    NULL,
    REASONDESCRIPTION VARCHAR(300)   NULL,
    CONSTRAINT FK_Medications_Patient FOREIGN KEY (PATIENT) REFERENCES dbo.patients(Id)
);
GO

-- 8. SDOH Community Vulnerability Lookup Table (Custom Enrichment)
IF OBJECT_ID('dbo.sdoh_zip_index', 'U') IS NOT NULL DROP TABLE dbo.sdoh_zip_index;
CREATE TABLE dbo.sdoh_zip_index (
    ZIP                     VARCHAR(20)  NOT NULL PRIMARY KEY,
    CITY                    VARCHAR(100) NULL,
    [STATE]                 VARCHAR(50)  NULL,
    SVI_Score               DECIMAL(4,2) NOT NULL, -- 0.00 (Lowest Risk) to 1.00 (Highest Risk)
    SDOH_Risk_Tier          VARCHAR(20)  NOT NULL, -- Low, Medium, High
    Transit_Barrier_Flag    BIT          NOT NULL,
    Food_Desert_Flag        BIT          NOT NULL,
    Primary_SDOH_Barrier    VARCHAR(100) NOT NULL
);
GO

-- Performance Indexes for HEDIS Measure Queries
CREATE NONCLUSTERED INDEX IX_Conditions_Patient_Code   ON dbo.conditions (PATIENT, CODE) INCLUDE ([START], [STOP], [DESCRIPTION]);
CREATE NONCLUSTERED INDEX IX_Observations_Patient_Code ON dbo.observations (PATIENT, CODE, [DATE]) INCLUDE ([VALUE]);
CREATE NONCLUSTERED INDEX IX_Encounters_Patient_Start  ON dbo.encounters (PATIENT, [START]) INCLUDE (ENCOUNTERCLASS, PROVIDER, TOTAL_CLAIM_COST);
GO
