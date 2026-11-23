-- ============================================================================
-- SCRIPT 02: NCQA HEDIS GSD (Glycemic Status Assessment for Patients with Diabetes)
-- Target: Members aged 18-75 with Diabetes; Compliant if HbA1c < 8.0%
-- ============================================================================

USE MedicareAdvantage_PHM;
GO

CREATE OR ALTER VIEW dbo.vw_HEDIS_GSD_CareGaps AS
WITH Config AS (
    SELECT MeasurementYear FROM dbo.phm_config WHERE ConfigID = 1
),
EligibleDiabetics AS (
    -- 1. Denominator: Members aged 18-75 with Type 1/2 Diabetes, excluding deceased/hospice
    SELECT DISTINCT
        p.Id AS MemberID,
        cfg.MeasurementYear
    FROM dbo.patients p
    CROSS JOIN Config cfg
    INNER JOIN dbo.conditions c ON p.Id = c.PATIENT
    WHERE c.[DESCRIPTION] LIKE '%Diabetes%'
      AND YEAR(c.[START]) <= cfg.MeasurementYear
      AND (c.[STOP] IS NULL OR YEAR(c.[STOP]) >= cfg.MeasurementYear - 1)
      AND (p.DEATHDATE IS NULL OR YEAR(p.DEATHDATE) > cfg.MeasurementYear)
      AND DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) BETWEEN 18 AND 75
      -- 2. Clinical Exclusions (Hospice & Palliative Care)
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.conditions ex
          WHERE ex.PATIENT = p.Id
            AND (ex.[DESCRIPTION] LIKE '%Hospice%' OR ex.[DESCRIPTION] LIKE '%Palliative%')
            AND YEAR(ex.[START]) <= cfg.MeasurementYear
      )
),
LatestHbA1c AS (
    -- 3. Numerator input: Most recent HbA1c lab result in Measurement Year
    -- NCQA Rule: Same-day ties broken by lowest numeric value
    SELECT
        o.PATIENT AS MemberID,
        TRY_CAST(o.[VALUE] AS DECIMAL(5,2)) AS Latest_HbA1c,
        CAST(o.[DATE] AS DATE) AS HbA1c_Date,
        ROW_NUMBER() OVER (
            PARTITION BY o.PATIENT
            ORDER BY o.[DATE] DESC, TRY_CAST(o.[VALUE] AS DECIMAL(5,2)) ASC
        ) AS rn
    FROM dbo.observations o
    CROSS JOIN Config cfg
    WHERE (o.CODE IN ('4548-4', '17855-8', '17856-6', '4549-2')
           OR o.[DESCRIPTION] LIKE '%Hemoglobin A1c%')
      AND YEAR(o.[DATE]) = cfg.MeasurementYear
      AND TRY_CAST(o.[VALUE] AS DECIMAL(5,2)) IS NOT NULL
)
-- 4. Final GSD Compliance Classification
SELECT
    d.MemberID,
    d.MeasurementYear,
    1 AS Is_GSD_Eligible,
    h.HbA1c_Date,
    h.Latest_HbA1c,
    CASE
        WHEN h.Latest_HbA1c IS NULL THEN 'Open Gap - No HbA1c Test'
        WHEN h.Latest_HbA1c > 9.0   THEN 'Open Gap - Poor Control (>9.0%)'
        WHEN h.Latest_HbA1c >= 8.0  THEN 'Watchlist (8.0% - 9.0%)'
        ELSE 'Compliant (<8.0%)'
    END AS GSD_Gap_Status,
    CASE
        WHEN h.Latest_HbA1c IS NULL OR h.Latest_HbA1c > 9.0 THEN 1
        ELSE 0
    END AS Is_GSD_Open_Gap
FROM EligibleDiabetics d
LEFT JOIN LatestHbA1c h
    ON d.MemberID = h.MemberID
   AND h.rn = 1;
GO
