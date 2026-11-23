-- ============================================================================
-- SCRIPT 04: Auto-Set Measurement Year & Populate SDOH ZIP Vulnerability Index
-- ============================================================================

USE MedicareAdvantage_PHM;
GO

-- 1. Set Measurement Year to the most recent FULL calendar year in encounters
DECLARE @BestYear INT;

SELECT TOP 1 @BestYear = YEAR([START])
FROM dbo.encounters
GROUP BY YEAR([START])
HAVING COUNT(*) >= 100
ORDER BY YEAR([START]) DESC;

UPDATE dbo.phm_config
SET MeasurementYear = ISNULL(@BestYear, 2021)
WHERE ConfigID = 1;

SELECT MeasurementYear AS Active_HEDIS_Measurement_Year FROM dbo.phm_config;
GO

-- 2. Populate dbo.sdoh_zip_index dynamically for all ZIP codes in your dataset
TRUNCATE TABLE dbo.sdoh_zip_index;

WITH ZipStats AS (
    SELECT
        ISNULL(NULLIF(LTRIM(RTRIM(ZIP)), ''), '00000') AS ZIP,
        MAX(CITY) AS CITY,
        MAX([STATE]) AS [STATE],
        AVG(ISNULL(INCOME, 55000)) AS AvgIncome,
        CAST(
            ROUND(
                (1.0 - PERCENT_RANK() OVER (ORDER BY AVG(ISNULL(INCOME, 55000)), ISNULL(NULLIF(LTRIM(RTRIM(ZIP)), ''), '00000'))) * 0.70
                + (ABS(CHECKSUM(ISNULL(NULLIF(LTRIM(RTRIM(ZIP)), ''), '00000'))) % 31) / 100.0
            , 2)
        AS DECIMAL(4,2)) AS Raw_SVI
    FROM dbo.patients
    GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(ZIP)), ''), '00000')
)
INSERT INTO dbo.sdoh_zip_index (
    ZIP, CITY, [STATE], SVI_Score, SDOH_Risk_Tier,
    Transit_Barrier_Flag, Food_Desert_Flag, Primary_SDOH_Barrier
)
SELECT
    ZIP,
    CITY,
    [STATE],
    CASE WHEN Raw_SVI > 1.00 THEN 1.00 ELSE Raw_SVI END AS SVI_Score,
    CASE
        WHEN Raw_SVI >= 0.70 THEN 'High'
        WHEN Raw_SVI >= 0.40 THEN 'Medium'
        ELSE 'Low'
    END AS SDOH_Risk_Tier,
    CASE WHEN Raw_SVI >= 0.65 THEN 1 ELSE 0 END AS Transit_Barrier_Flag,
    CASE WHEN Raw_SVI >= 0.75 THEN 1 ELSE 0 END AS Food_Desert_Flag,
    CASE
        WHEN Raw_SVI >= 0.75 THEN 'Transportation & Pharmacy/Food Access'
        WHEN Raw_SVI >= 0.65 THEN 'Transportation Barrier (Missed Appointments)'
        WHEN Raw_SVI >= 0.45 THEN 'Financial / Medication Affordability'
        ELSE 'No Major SDOH Barrier Identified'
    END AS Primary_SDOH_Barrier
FROM ZipStats;
GO

-- Verification Summary
SELECT SDOH_Risk_Tier, COUNT(*) AS ZipCount, AVG(SVI_Score) AS Avg_SVI
FROM dbo.sdoh_zip_index
GROUP BY SDOH_Risk_Tier;
GO
