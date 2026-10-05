# Power BI Dashboard Guide
**Monthly Revenue Forecasting & Budget Variance — Walmart FY2013**

Build the final dashboard in **Power BI Desktop** (Windows) from the files in `data/powerbi/`. It takes about 2–3 hours the first time. Save it as `powerbi/revenue_dashboard.pbix`.

> **On a Mac?** Power BI Desktop only runs on Windows. Use a Windows PC, Parallels, or build the same pages in **Tableau Public**; the Tableau equivalents are at the end of this guide.

---

## 1. Files to load (Get Data → Text/CSV → Transform Data)

| File | Rows | Contents | Type |
|---|---|---|---|
| `fact_monthly_sales.csv` | 97,569 | Revenue by store × department × month, Feb 2010 – Sep 2012 | Fact |
| `fact_budget.csv` | 36,736 | FY2013 budget by store × department × month | Fact |
| `fact_forecast.csv` | 236 | Python forecasts: company total, store type, store; backtest and Oct 2012 – Jan 2013 | Fact |
| `fact_weekly_store_sales.csv` | 6,435 | Weekly sales per store with holiday flag | Fact |
| `fact_store_week_features.csv` | 6,435 | Temperature, fuel price, CPI, unemployment, markdowns per store-week | Fact |
| `dim_store.csv` | 45 | Store type (A/B/C) and size | Dimension |
| `dim_department.csv` | 81 | Departments | Dimension |
| `dim_month.csv` | 36 | Month calendar with Walmart fiscal year / month / quarter | Dimension |
| `dim_budget_assumptions.csv` | 3 | Growth target per store type | Dimension |
| `model_backtest_scores.csv` | 6 | Accuracy of each forecasting method (MAPE, MAE, bias) | Table |
| `store_latest_estimate.csv` | 45 | Full-year latest estimate per store | Table |

## 2. Power Query steps
1. **Data types:** every `month_start` and `week_end_date` → **Date**; `revenue`, `budget_amount`, `forecast`, `lower_80`, `upper_80`, `weekly_sales` → **Fixed decimal (currency)**; `growth_target`, `MAPE`, `Bias`, `variance_pct`, `ytd_growth` → **Percentage**.
2. **fact_forecast:** add a column `store_id` = `if [level] = "Store" then Number.FromText([level_value]) else null` (Whole Number). Add `store_type` = `if [level] = "Store type" then [level_value] else null`.
3. **dim_month:** add `Month Label` = `Date.ToText([month_start], "MMM yyyy")` and `FY Label` = `"FY" & Text.From([fiscal_year])`.
4. **Close & Apply.**

## 3. Data model (Model view)
All relationships are **one-to-many, single direction**, dimension → fact.

| One side | Many side |
|---|---|
| `dim_month[month_start]` | `fact_monthly_sales[month_start]` |
| `dim_month[month_start]` | `fact_budget[month_start]` |
| `dim_month[month_start]` | `fact_forecast[month_start]` |
| `dim_store[store_id]` | `fact_monthly_sales[store_id]`, `fact_budget[store_id]`, `fact_forecast[store_id]`, `fact_weekly_store_sales[store_id]`, `fact_store_week_features[store_id]`, `store_latest_estimate[store_id]` |
| `dim_department[dept_id]` | `fact_monthly_sales[dept_id]`, `fact_budget[dept_id]` |
| `dim_budget_assumptions[store_type]` | `dim_store[store_type]` |

Sort `dim_month[Month Label]` by `month_start`. Hide key columns on the fact tables.

## 4. DAX measures
Create an empty table `_Measures` (Enter data → Load) and add these. The comment after each measure gives its format.

### Actuals and growth
```DAX
Revenue = SUM ( fact_monthly_sales[revenue] )                                      -- $ #,0

Revenue LY =
SUMX (
    VALUES ( dim_month[month_start] ),
    VAR m = dim_month[month_start]
    RETURN CALCULATE ( [Revenue], ALL ( dim_month ), dim_month[month_start] = EDATE ( m, -12 ) )
)

YoY Growth % = DIVIDE ( [Revenue] - [Revenue LY], [Revenue LY] )                  -- %, 2 dp

Revenue per Sq Ft = DIVIDE ( [Revenue], SUM ( dim_store[size_sqft] ) )
```

### Budget and variance
```DAX
Budget = SUM ( fact_budget[budget_amount] )

-- budget only for months that already have actuals (fair YTD comparison)
Budget YTD =
SUMX (
    VALUES ( dim_month[month_start] ),
    IF ( NOT ISBLANK ( [Revenue] ), [Budget] )
)

Variance = [Revenue] - [Budget YTD]                                                -- + favourable
Variance % = DIVIDE ( [Variance], [Budget YTD] )
Status = IF ( [Variance] >= 0, "Favourable", "Unfavourable" )

Stores On Budget =
COUNTROWS ( FILTER ( VALUES ( dim_store[store_id] ), [Variance] >= 0 ) )

Leap Day Effect =                                                                 -- Feb 2012 had 29 days
CALCULATE ( [Revenue], dim_month[month_start] = DATE ( 2012, 2, 1 ) ) / 29
```

### Forecast and latest estimate
```DAX
Forecast (Company) =
CALCULATE ( SUM ( fact_forecast[forecast] ),
            fact_forecast[level] = "Total", fact_forecast[purpose] = "Forecast" )

Forecast Low 80 =
CALCULATE ( SUM ( fact_forecast[lower_80] ),
            fact_forecast[level] = "Total", fact_forecast[purpose] = "Forecast" )

Forecast High 80 =
CALCULATE ( SUM ( fact_forecast[upper_80] ),
            fact_forecast[level] = "Total", fact_forecast[purpose] = "Forecast" )

Forecast (Store run-rate) =
CALCULATE ( SUM ( fact_forecast[forecast] ), fact_forecast[level] = "Store" )

-- company view: actual where we have it, Holt-Winters forecast for Oct-Jan
Latest Estimate =
SUMX (
    VALUES ( dim_month[month_start] ),
    VAR a = [Revenue]
    RETURN IF ( NOT ISBLANK ( a ), a, [Forecast (Company)] )
)

-- store view: actual + store run-rate forecast (use on store pages)
Latest Estimate (Store) =
SUMX (
    VALUES ( dim_month[month_start] ),
    VAR a = [Revenue]
    RETURN IF ( NOT ISBLANK ( a ), a, [Forecast (Store run-rate)] )
)

LE vs Budget = [Latest Estimate] - [Budget]
LE vs Budget % = DIVIDE ( [LE vs Budget], [Budget] )

Backtest Forecast (Holt-Winters) =
CALCULATE ( SUM ( fact_forecast[forecast] ), fact_forecast[purpose] = "Backtest",
            fact_forecast[model] = "Holt-Winters" )
```

### What-if growth target (makes the budget interactive)
**Modeling → New parameter → Numeric range**: name `Growth Change`, min −0.03, max 0.03, increment 0.005, default 0. Then:
```DAX
Budget (What-if) =
SUMX (
    VALUES ( dim_store[store_type] ),
    VAR g = LOOKUPVALUE ( dim_budget_assumptions[growth_target],
                          dim_budget_assumptions[store_type], dim_store[store_type] )
    RETURN [Budget] / ( 1 + g ) * ( 1 + g + [Growth Change Value] )
)
Variance (What-if) = [Revenue] - SUMX ( VALUES ( dim_month[month_start] ),
                                         IF ( NOT ISBLANK ( [Revenue] ), [Budget (What-if)] ) )
```
Moving the slider shows how the variance would look with a higher or lower growth target.

## 5. Report pages
Apply the theme first: **View → Themes → Browse** → `powerbi/theme/revenue_theme.json`.
Slicers on every page (sync them): `dim_month[FY Label]`, `dim_store[store_type]`.

### Page 1 — Executive summary (filter: FY2013)
| Visual | Fields |
|---|---|
| 6 **cards** | `Revenue` (title "YTD actual"), `Budget YTD`, `Variance`, `Variance %`, `Latest Estimate`, `LE vs Budget %` |
| **Line and clustered column** | X `dim_month[Month Label]`; columns `Latest Estimate`; line `Budget` |
| **Waterfall** | Category `dim_month[Month Label]`, Y `Variance` (shows how the YTD lead built up and shrank) |
| **Text box** | 3 key findings + 3 recommendations from the README |

### Page 2 — Store & department variance
| Visual | Fields |
|---|---|
| **Bar chart** | Y `dim_store[store_id]`, X `Variance %`, sorted ascending; conditional colour (green ≥ 0, orange < 0) |
| **Matrix** | Rows `dim_store[store_type]` → `store_id`; values `Budget YTD`, `Revenue`, `Variance`, `Variance %`, `Latest Estimate (Store)`; background colour on `Variance %` |
| **Table** | `dim_department[dept_name]`, `Budget YTD`, `Revenue`, `Variance` — top 10 by absolute variance (filter pane: Top N) |
| **Card** | `Stores On Budget` |

### Page 3 — Forecast
| Visual | Fields |
|---|---|
| **Line chart** | X `dim_month[month_start]` (all months); lines `Revenue`, `Forecast (Company)`, `Forecast Low 80`, `Forecast High 80`, `Budget` (format Low/High as thin dashed lines) |
| **Line chart (backtest)** | X Feb–Sep 2012; lines `Revenue`, `Backtest Forecast (Holt-Winters)`, `Budget` |
| **Table** | `model_backtest_scores`: model, MAPE, MAE, Bias, sorted by MAPE |
| **Clustered bar** | `store_latest_estimate`: store_id vs `variance` (bottom 10) — "stores at risk" |

### Page 4 — Trends & seasonality
| Visual | Fields |
|---|---|
| **Line chart** | X `dim_month[fiscal_month]` (labels Feb…Jan), Y `Revenue`, Legend `FY Label` — three years on one chart |
| **Line chart** | X `fact_weekly_store_sales[week_end_date]`, Y sum of `weekly_sales`; add `is_holiday` to tooltips |
| **Column chart** | X `dim_store[store_type]`, Y `Revenue per Sq Ft` |

### Page 5 — What-if & drivers
| Visual | Fields |
|---|---|
| **Slider** | `Growth Change` parameter |
| **Cards** | `Budget (What-if)`, `Variance (What-if)` |
| **Scatter** | `fact_store_week_features[temperature_f]` vs sum of `fact_weekly_store_sales[weekly_sales]` (shows the weak relationship) |

## 6. Expected numbers (check your model)
With **FY2013** selected and no other filters: **YTD actual $1,634.1M · YTD budget $1,624.6M · Variance +$9.5M (+0.59%) · Full-year budget $2,524.3M · Latest estimate $2,518.7M (−0.22%) · 32 stores on budget.**

## 7. Building it in Tableau Public instead (Mac)
Connect to the same CSVs, relate them on `month_start` / `store_id` / `dept_id` (Data Source → drag tables to relate), then create calculated fields:

| Power BI measure | Tableau calculated field |
|---|---|
| `Revenue` | `SUM([revenue])` |
| `Budget YTD` | `IF SUM([revenue]) > 0 THEN SUM([budget_amount]) END` (at month level) |
| `Variance %` | `(SUM([revenue]) - [Budget YTD]) / [Budget YTD]` |
| `Latest Estimate` | `IFNULL(SUM([revenue]), SUM([forecast]))` with forecast filtered to level = "Total", purpose = "Forecast" |
| What-if parameter | **Create Parameter** "Growth change" (−3% to +3%), then `SUM([budget_amount]) / (1 + [growth_target]) * (1 + [growth_target] + [Growth change])` |

Use the same five pages as dashboards, then **File → Save to Tableau Public** to get a shareable link.
