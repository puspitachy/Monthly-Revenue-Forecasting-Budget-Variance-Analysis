-- =====================================================================
-- 05_forecast_queries.sql — questions that need the forecast table.
-- The Python notebook writes forecasts into the `forecast` table, then
-- runs this file. Results go to sql/query_results/.
-- =====================================================================


-- Q20: Backtest — how close was each model (and the budget) to actual Feb - Sep 2012?
WITH bt AS (
    SELECT f.model, f.month_start, f.forecast, t.revenue AS actual
    FROM forecast f
    JOIN vw_monthly_total t ON t.month_start = f.month_start
    WHERE f.level = 'Total' AND f.purpose = 'Backtest'
    UNION ALL
    SELECT 'Budget (LY x growth target)', b.month_start, b.budget, b.actual
    FROM vw_bva_month b WHERE b.actual IS NOT NULL
)
SELECT
    model,
    COUNT(*)                                                        AS months,
    ROUND(100.0 * AVG(ABS(forecast - actual) / actual), 2)          AS mape_pct,
    ROUND(AVG(ABS(forecast - actual)), 0)                           AS mae,
    ROUND(100.0 * (SUM(forecast) - SUM(actual)) / SUM(actual), 2)   AS bias_pct
FROM bt
GROUP BY model
ORDER BY mape_pct;


-- Q21: Full-year FY2013 latest estimate = actual (Feb-Sep) + forecast (Oct-Jan) vs budget
WITH months AS (
    SELECT b.month_start, b.fiscal_month, b.budget, b.actual,
           f.forecast, f.lower_80, f.upper_80
    FROM vw_bva_month b
    LEFT JOIN forecast f ON f.month_start = b.month_start
                        AND f.level = 'Total' AND f.purpose = 'Forecast'
)
SELECT
    month_start, fiscal_month,
    ROUND(budget, 0)                                         AS budget,
    ROUND(actual, 0)                                         AS actual,
    ROUND(forecast, 0)                                       AS forecast,
    ROUND(COALESCE(actual, forecast), 0)                     AS latest_estimate,
    ROUND(COALESCE(actual, forecast) - budget, 0)            AS variance_vs_budget,
    CASE WHEN actual IS NOT NULL THEN 'Actual' ELSE 'Forecast' END AS basis,
    ROUND(SUM(COALESCE(actual, forecast) - budget) OVER (ORDER BY month_start), 0) AS cumulative_variance
FROM months
ORDER BY month_start;


-- Q22: Latest estimate vs budget by store type (full FY2013)
WITH le AS (
    SELECT s.store_type, SUM(v.actual) AS ytd_actual, SUM(v.budget) AS full_budget
    FROM vw_bva_store_month v JOIN stores s ON s.store_id = v.store_id
    GROUP BY s.store_type
), fc AS (
    SELECT level_value AS store_type, SUM(forecast) AS rest_of_year
    FROM forecast WHERE level = 'Store type' AND purpose = 'Forecast'
    GROUP BY level_value
)
SELECT
    le.store_type,
    ROUND(le.full_budget, 0)                                        AS fy2013_budget,
    ROUND(le.ytd_actual, 0)                                         AS ytd_actual,
    ROUND(fc.rest_of_year, 0)                                       AS forecast_oct_jan,
    ROUND(le.ytd_actual + fc.rest_of_year, 0)                       AS latest_estimate,
    ROUND(le.ytd_actual + fc.rest_of_year - le.full_budget, 0)      AS variance,
    ROUND(100.0 * (le.ytd_actual + fc.rest_of_year - le.full_budget) / le.full_budget, 2) AS variance_pct
FROM le JOIN fc ON fc.store_type = le.store_type
ORDER BY le.store_type;
