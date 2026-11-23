-- ============================================================================
-- SCRIPT 05: Master Population Health & Care Management View (Power BI Source)
-- Dependencies: Run Scripts 01, 02, 03, and 04 prior to this script
-- ============================================================================

USE MedicareAdvantage_PHM;
GO

CREATE OR ALTER VIEW dbo.vw_PHM_Member_Summary AS
WITH Config AS (
    SELECT MeasurementYear FROM dbo.phm_config WHERE ConfigID = 1
),
Utilization_MY AS (
    -- Measurement Year Claims, ED Visits, Inpatient Admissions & Wellness Visits
    SELECT
        e.PATIENT AS MemberID,
        COUNT(*) AS Total_Encounters_MY,
        SUM(CASE WHEN e.ENCOUNTERCLASS = 'emergency' THEN 1 ELSE 0 END) AS ED_Visits_MY,
        SUM(CASE WHEN e.ENCOUNTERCLASS = 'inpatient' THEN 1 ELSE 0 END) AS Inpatient_Admits_MY,
        SUM(CASE WHEN e.ENCOUNTERCLASS = 'wellness'  THEN 1 ELSE 0 END) AS Wellness_Visits_MY,
        SUM(ISNULL(e.TOTAL_CLAIM_COST, 0)) AS Annual_Claim_Spend_MY
    FROM dbo.encounters e
    CROSS JOIN Config cfg
    WHERE YEAR(e.[START]) = cfg.MeasurementYear
    GROUP BY e.PATIENT
),
ChronicConditions AS (
    -- Active Chronic Comorbidity Count per Member
    SELECT
        c.PATIENT AS MemberID,
        COUNT(DISTINCT c.CODE) AS Active_Condition_Count
    FROM dbo.conditions c
    CROSS JOIN Config cfg
    WHERE YEAR(c.[START]) <= cfg.MeasurementYear
      AND (c.[STOP] IS NULL OR YEAR(c.[STOP]) >= cfg.MeasurementYear)
    GROUP BY c.PATIENT
),
AttributedPCP AS (
    -- Provider Attribution: Most recent outpatient/wellness provider
    SELECT
        e.PATIENT AS MemberID,
        pr.[NAME] AS Attributed_Provider,
        pr.SPECIALITY AS Provider_Specialty,
        ROW_NUMBER() OVER (
            PARTITION BY e.PATIENT
            ORDER BY e.[START] DESC
        ) AS rn
    FROM dbo.encounters e
    INNER JOIN dbo.providers pr ON e.PROVIDER = pr.Id
    WHERE e.ENCOUNTERCLASS IN ('wellness', 'ambulatory', 'outpatient')
),
BaseMetrics AS (
    SELECT
        p.Id AS MemberID,
        LTRIM(RTRIM(ISNULL(p.[FIRST], '') + ' ' + ISNULL(p.[LAST], ''))) AS MemberName,
        DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) AS MemberAge,
        CASE
            WHEN DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) < 45 THEN '18-44'
            WHEN DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) < 65 THEN '45-64'
            WHEN DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) < 75 THEN '65-74'
            ELSE '75+'
        END AS Age_Band,
        p.GENDER,
        p.RACE,
        p.CITY,
        p.[STATE],
        ISNULL(NULLIF(LTRIM(RTRIM(p.ZIP)), ''), '00000') AS ZIP,
        cfg.MeasurementYear,

        -- Provider Attribution
        ISNULL(pcp.Attributed_Provider, 'Unassigned PCP') AS Attributed_Provider,
        ISNULL(pcp.Provider_Specialty, 'General Practice') AS Provider_Specialty,

        -- HEDIS GSD (Diabetes)
        ISNULL(gsd.Is_GSD_Eligible, 0) AS Is_GSD_Eligible,
        gsd.HbA1c_Date,
        gsd.Latest_HbA1c,
        ISNULL(gsd.GSD_Gap_Status, 'Not Eligible') AS GSD_Gap_Status,
        ISNULL(gsd.Is_GSD_Open_Gap, 0) AS Is_GSD_Open_Gap,

        -- HEDIS CBP (Hypertension)
        ISNULL(cbp.Is_CBP_Eligible, 0) AS Is_CBP_Eligible,
        cbp.Latest_BP_Date,
        cbp.Systolic_BP,
        cbp.Diastolic_BP,
        ISNULL(cbp.CBP_Gap_Status, 'Not Eligible') AS CBP_Gap_Status,
        ISNULL(cbp.Is_CBP_Open_Gap, 0) AS Is_CBP_Open_Gap,

        -- Combined Open Care Gaps
        ISNULL(gsd.Is_GSD_Open_Gap, 0) + ISNULL(cbp.Is_CBP_Open_Gap, 0) AS Total_Open_Care_Gaps,

        -- Utilization & Financial KPIs
        ISNULL(cc.Active_Condition_Count, 0) AS Active_Condition_Count,
        ISNULL(u.ED_Visits_MY, 0) AS ED_Visits_MY,
        ISNULL(u.Inpatient_Admits_MY, 0) AS Inpatient_Admits_MY,
        ISNULL(u.Wellness_Visits_MY, 0) AS Wellness_Visits_MY,
        ISNULL(u.Annual_Claim_Spend_MY, 0) AS Annual_Claim_Spend_MY,
        CAST(ISNULL(u.Annual_Claim_Spend_MY, 0) / 12.0 AS DECIMAL(12,2)) AS Estimated_PMPM,
        ISNULL(p.HEALTHCARE_EXPENSES, 0) AS Lifetime_Healthcare_Expenses,

        -- SDOH Enrichment
        ISNULL(sdoh.SVI_Score, 0.50) AS SVI_Score,
        ISNULL(sdoh.SDOH_Risk_Tier, 'Medium') AS SDOH_Risk_Tier,
        ISNULL(sdoh.Transit_Barrier_Flag, 0) AS Transit_Barrier_Flag,
        ISNULL(sdoh.Primary_SDOH_Barrier, 'Not Assessed') AS Primary_SDOH_Barrier,

        -- Weighted Composite Clinical + SDOH Risk Score (0 - 100 scale)
        (
            (ISNULL(gsd.Is_GSD_Open_Gap, 0) * 20) +
            (ISNULL(cbp.Is_CBP_Open_Gap, 0) * 15) +
            (CASE WHEN ISNULL(u.ED_Visits_MY, 0) >= 2 THEN 25
                  WHEN ISNULL(u.ED_Visits_MY, 0) = 1  THEN 12 ELSE 0 END) +
            (CASE WHEN ISNULL(u.Inpatient_Admits_MY, 0) >= 1 THEN 20 ELSE 0 END) +
            (CASE WHEN ISNULL(cc.Active_Condition_Count, 0) >= 5 THEN 10 ELSE 0 END) +
            (CASE WHEN ISNULL(sdoh.SDOH_Risk_Tier, 'Low') = 'High' THEN 10
                  WHEN ISNULL(sdoh.SDOH_Risk_Tier, 'Low') = 'Medium' THEN 5 ELSE 0 END)
        ) AS Composite_Risk_Score
    FROM dbo.patients p
    CROSS JOIN Config cfg
    LEFT JOIN dbo.vw_HEDIS_GSD_CareGaps gsd ON p.Id = gsd.MemberID
    LEFT JOIN dbo.vw_HEDIS_CBP_CareGaps cbp ON p.Id = cbp.MemberID
    LEFT JOIN Utilization_MY u              ON p.Id = u.MemberID
    LEFT JOIN ChronicConditions cc          ON p.Id = cc.MemberID
    LEFT JOIN AttributedPCP pcp             ON p.Id = pcp.MemberID AND pcp.rn = 1
    LEFT JOIN dbo.sdoh_zip_index sdoh       ON ISNULL(NULLIF(LTRIM(RTRIM(p.ZIP)), ''), '00000') = sdoh.ZIP
    -- Exclude deceased members & pediatric patients (<18) for adult Medicare/PHM scope
    WHERE (p.DEATHDATE IS NULL OR YEAR(p.DEATHDATE) > cfg.MeasurementYear)
      AND DATEDIFF(YEAR, p.BIRTHDATE, DATEFROMPARTS(cfg.MeasurementYear, 12, 31)) >= 18
)
SELECT
    *,
    CASE
        WHEN Composite_Risk_Score >= 45 THEN 'High Risk'
        WHEN Composite_Risk_Score >= 20 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS Member_Risk_Tier,
    CASE
        WHEN Total_Open_Care_Gaps >= 2 AND Transit_Barrier_Flag = 1
            THEN 'Priority 1: Nurse Care Manager Call + Ride-Share / Mobile Phlebotomy'
        WHEN Total_Open_Care_Gaps >= 1 AND (ED_Visits_MY >= 1 OR Inpatient_Admits_MY >= 1)
            THEN 'Priority 1: Transitional Care Management (TCM) + PCP Follow-up'
        WHEN Is_GSD_Open_Gap = 1
            THEN 'Priority 2: Schedule HbA1c Lab & Diabetes Educator Outreach'
        WHEN Is_CBP_Open_Gap = 1
            THEN 'Priority 2: Home BP Cuff Dispatch & Telehealth Medication Review'
        WHEN Wellness_Visits_MY = 0 AND MemberAge >= 65
            THEN 'Priority 3: Annual Wellness Visit (AWV) Reminder Campaign'
        ELSE 'Routine Monitoring'
    END AS Recommended_Intervention
FROM BaseMetrics;
GO

-- Sanity Check Verification Query
SELECT
    COUNT(*) AS Active_Adult_Members,
    SUM(Is_GSD_Eligible) AS GSD_Eligible,
    SUM(Is_GSD_Open_Gap) AS GSD_Open_Gaps,
    SUM(Is_CBP_Eligible) AS CBP_Eligible,
    SUM(Is_CBP_Open_Gap) AS CBP_Open_Gaps,
    AVG(Estimated_PMPM)  AS Avg_PMPM
FROM dbo.vw_PHM_Member_Summary;
GO
