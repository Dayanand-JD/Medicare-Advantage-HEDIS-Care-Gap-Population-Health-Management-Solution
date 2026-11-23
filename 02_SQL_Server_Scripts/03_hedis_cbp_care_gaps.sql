-- ============================================================================
-- SCRIPT 03: NCQA HEDIS CBP (Controlling High Blood Pressure) Care-Gap Engine
-- Target: Members aged 18-85 with Hypertension; Compliant if BP < 140/90 mmHg
-- ============================================================================

USE MedicareAdvantage_PHM;
GO

CREATE OR ALTER VIEW dbo.vw_HEDIS_CBP_CareGaps AS
WITH Config AS (
    SELECT MeasurementYear FROM dbo.phm_config WHERE ConfigID = 1
),
EligibleHypertension AS (
    -- 1. Denominator: Members aged 18-85 with active/historical Hypertension
    SELECT
        p.Id AS MemberID,
        MIN(c.[START]) AS First_HTN_Date,
        DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) AS MemberAge,
        cfg.MeasurementYear
    FROM dbo.patients p
    CROSS JOIN Config cfg
    INNER JOIN dbo.conditions c ON p.Id = c.PATIENT
    WHERE (c.CODE = '59621000' OR c.[DESCRIPTION] LIKE '%Hypertension%')
      AND YEAR(c.[START]) <= cfg.MeasurementYear
      AND (c.[STOP] IS NULL OR YEAR(c.[STOP]) >= cfg.MeasurementYear - 1)
      AND (p.DEATHDATE IS NULL OR YEAR(p.DEATHDATE) > cfg.MeasurementYear)
      AND DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) BETWEEN 18 AND 85
      -- 2. Clinical Exclusions (Hospice, Palliative, ESRD/Dialysis, Kidney Transplant, Pregnancy)
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.conditions ex
          WHERE ex.PATIENT = p.Id
            AND YEAR(ex.[START]) <= cfg.MeasurementYear
            AND (ex.[STOP] IS NULL OR YEAR(ex.[STOP]) >= cfg.MeasurementYear)
            AND (
                ex.[DESCRIPTION] LIKE '%Hospice%'
                OR ex.[DESCRIPTION] LIKE '%Palliative%'
                OR ex.[DESCRIPTION] LIKE '%End stage renal%'
                OR ex.[DESCRIPTION] LIKE '%End-stage renal%'
                OR ex.[DESCRIPTION] LIKE '%Dialysis%'
                OR ex.[DESCRIPTION] LIKE '%Kidney transplant%'
                OR (ex.[DESCRIPTION] LIKE '%Pregnan%' AND YEAR(ex.[START]) = cfg.MeasurementYear)
            )
      )
    GROUP BY p.Id, p.BIRTHDATE, cfg.MeasurementYear
),
DailyBloodPressures AS (
    -- 3. Pivot Systolic (8480-6) and Diastolic (8462-4) per member per day
    -- NCQA Rule: If multiple readings occur on the same date, take the LOWEST values
    SELECT
        o.PATIENT AS MemberID,
        CAST(o.[DATE] AS DATE) AS BP_Date,
        MIN(CASE WHEN o.CODE = '8480-6' THEN TRY_CAST(o.[VALUE] AS DECIMAL(5,1)) END) AS Systolic_BP,
        MIN(CASE WHEN o.CODE = '8462-4' THEN TRY_CAST(o.[VALUE] AS DECIMAL(5,1)) END) AS Diastolic_BP
    FROM dbo.observations o
    CROSS JOIN Config cfg
    WHERE o.CODE IN ('8480-6', '8462-4')
      AND YEAR(o.[DATE]) = cfg.MeasurementYear
      AND TRY_CAST(o.[VALUE] AS DECIMAL(5,1)) IS NOT NULL
    GROUP BY o.PATIENT, CAST(o.[DATE] AS DATE)
    HAVING MIN(CASE WHEN o.CODE = '8480-6' THEN TRY_CAST(o.[VALUE] AS DECIMAL(5,1)) END) IS NOT NULL
       AND MIN(CASE WHEN o.CODE = '8462-4' THEN TRY_CAST(o.[VALUE] AS DECIMAL(5,1)) END) IS NOT NULL
),
LatestValidBP AS (
    -- 4. Select the most recent BP reading ON OR AFTER the Hypertension diagnosis
    SELECT
        e.MemberID,
        bp.BP_Date,
        bp.Systolic_BP,
        bp.Diastolic_BP,
        ROW_NUMBER() OVER (
            PARTITION BY e.MemberID
            ORDER BY bp.BP_Date DESC
        ) AS rn
    FROM EligibleHypertension e
    INNER JOIN DailyBloodPressures bp
        ON e.MemberID = bp.MemberID
       AND bp.BP_Date >= e.First_HTN_Date
)
-- 5. Final CBP Compliance Classification
SELECT
    e.MemberID,
    e.MeasurementYear,
    1 AS Is_CBP_Eligible,
    bp.BP_Date AS Latest_BP_Date,
    bp.Systolic_BP,
    bp.Diastolic_BP,
    CASE
        WHEN bp.Systolic_BP IS NULL THEN 'Open Gap - No BP Reading'
        WHEN bp.Systolic_BP < 140.0 AND bp.Diastolic_BP < 90.0 THEN 'Compliant (<140/90)'
        ELSE 'Open Gap - Uncontrolled BP (>=140/90)'
    END AS CBP_Gap_Status,
    CASE
        WHEN bp.Systolic_BP IS NULL
          OR bp.Systolic_BP >= 140.0
          OR bp.Diastolic_BP >= 90.0 THEN 1
        ELSE 0
    END AS Is_CBP_Open_Gap
FROM EligibleHypertension e
LEFT JOIN LatestValidBP bp
    ON e.MemberID = bp.MemberID
   AND bp.rn = 1;
GO
