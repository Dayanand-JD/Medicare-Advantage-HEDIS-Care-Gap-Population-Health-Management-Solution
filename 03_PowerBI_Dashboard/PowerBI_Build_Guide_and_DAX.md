# Power BI Build Guide & DAX Measures (`PHM_HEDIS_Dashboard.pbix`)

> **Why isn't a `.pbix` binary pre-bundled?**  
> Microsoft `.pbix` files are proprietary Power BI Desktop binary packages containing an embedded Analysis Services (VertiPaq) engine that can only be compiled inside **Power BI Desktop**. This folder includes everything required to assemble and save `PHM_HEDIS_Dashboard.pbix` in under 10 minutes—including a ready-to-load 500-member synthetic dataset (`sample_vw_PHM_Member_Summary.csv`), all DAX measures below, and reference layout screenshots.

---

## Step 1: Connect Data Source in Power BI Desktop
Choose either option:
1. **Live SQL Server (Recommended for Portfolio Demo):**  
   `Home → Get Data → SQL Server` → Enter your local instance (e.g., `localhost\SQLEXPRESS`), database `MedicareAdvantage_PHM`, and load **`dbo.vw_PHM_Member_Summary`**.
2. **Instant Preview Mode (Zero SQL Setup):**  
   `Home → Get Data → Text/CSV` → Select `sample_vw_PHM_Member_Summary.csv` in this folder and rename the loaded query to `vw_PHM_Member_Summary`.

---

## Step 2: Create a What-If Parameter for CMS Star Rating Simulation
1. Go to **Modeling → New Parameter → Numeric Range**.
2. Name: `Target Compliance %` | Data Type: `Decimal number` | Min: `0.60` | Max: `0.95` | Increment: `0.01` | Default: `0.78`.
3. Add the generated slicer to **Page 1** and format as Percentage (`0%`).

---

## Step 3: Paste All DAX Measures (Create a `_Measures` Table)

```dax
// --- CORE POPULATION & FINANCIAL KPIs ---
Active Adult Members = COUNTROWS(vw_PHM_Member_Summary)

Total Open Care Gaps = SUM(vw_PHM_Member_Summary[Total_Open_Care_Gaps])

Average PMPM = AVERAGE(vw_PHM_Member_Summary[Estimated_PMPM])

Total Annual Claim Spend = SUM(vw_PHM_Member_Summary[Annual_Claim_Spend_MY])

High Risk Members =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    vw_PHM_Member_Summary[Member_Risk_Tier] = "High Risk"
)

Priority 1 Outreach Count =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    LEFT(vw_PHM_Member_Summary[Recommended_Intervention], 10) = "Priority 1"
)

// --- HEDIS GSD (DIABETES) METRICS ---
GSD Eligible Members =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    vw_PHM_Member_Summary[Is_GSD_Eligible] = 1
)

GSD Compliant Members =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    vw_PHM_Member_Summary[GSD_Gap_Status] = "Compliant (<8.0%)"
)

GSD Compliance Rate =
DIVIDE([GSD Compliant Members], [GSD Eligible Members], 0)

GSD Gaps Needed for Target =
VAR TargetPct = SELECTEDVALUE('Target Compliance %'[Target Compliance %], 0.78)
RETURN MAX(0, ROUNDUP((TargetPct * [GSD Eligible Members]) - [GSD Compliant Members], 0))

GSD Gaps Needed for 4-Star (78%) =
MAX(0, ROUNDUP((0.78 * [GSD Eligible Members]) - [GSD Compliant Members], 0))

// --- HEDIS CBP (HYPERTENSION) METRICS ---
CBP Eligible Members =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    vw_PHM_Member_Summary[Is_CBP_Eligible] = 1
)

CBP Compliant Members =
CALCULATE(
    COUNTROWS(vw_PHM_Member_Summary),
    vw_PHM_Member_Summary[CBP_Gap_Status] = "Compliant (<140/90)"
)

CBP Compliance Rate =
DIVIDE([CBP Compliant Members], [CBP Eligible Members], 0)

CBP Gaps Needed for Target =
VAR TargetPct = SELECTEDVALUE('Target Compliance %'[Target Compliance %], 0.78)
RETURN MAX(0, ROUNDUP((TargetPct * [CBP Eligible Members]) - [CBP Compliant Members], 0))

CBP Gaps Needed for 4-Star (78%) =
MAX(0, ROUNDUP((0.78 * [CBP Eligible Members]) - [CBP Compliant Members], 0))
```

---

## Step 4: Build the 3 Pages & Save as `PHM_HEDIS_Dashboard.pbix`
Match the layout shown in `screenshots/`:
* **Page 1 (`page1_executive_stars.png`):** 5 KPI Cards, GSD & CBP Compliance Clustered Bars with Constant Reference Lines at `0.78` (4-Star) and `0.85` (5-Star), What-If Parameter Slicer + Gaps Needed cards, and Provider Open Gap Stacked Bar Chart.
* **Page 2 (`page2_care_management_worklist.png`):** Risk Tier KPI Strip, Scatter Chart (`Composite_Risk_Score` vs `Annual_Claim_Spend_MY`, Size = `ED_Visits_MY`, Legend = `Member_Risk_Tier`), Intervention Priority Bar Chart, and Top Priority Nurse Outreach Table.
* **Page 3 (`page3_sdoh_equity.png`):** Clustered Column Chart (`GSD Compliance Rate` & `CBP Compliance Rate` by `SDOH_Risk_Tier`), Geographic Hotspot Bar/Map by `CITY`, Combo Chart (`Total_Open_Care_Gaps` + `Average PMPM` by `Age_Band`), and Primary SDOH Barrier Breakdown.
