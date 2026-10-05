-- =====================================================================
-- Monthly Revenue Forecasting & Budget Variance Analysis (Walmart data)
-- 04_analysis_queries.sql — business questions answered in SQL
--
-- Dialect: SQLite (database: data/revenue.db). Run 01_schema.sql,
-- load the CSVs, then 02_transform.sql and 03_views.sql first.
-- PostgreSQL: replace julianday()/date() with date arithmetic and
-- strftime('%Y-%m', d) with to_char(d, 'YYYY-MM').
-- Each query starts with "-- Qnn:"; scripts/02_build_database.py runs them
-- all and saves the results to sql/query_results/.
-- =====================================================================


-- Q01: Data overview
SELECT
    (SELECT COUNT(*) FROM weekly_sales)                         AS weekly_rows,
    (SELECT COUNT(DISTINCT week_end_date) FROM weekly_sales)    AS weeks,
    (SELECT MIN(week_end_date) FROM weekly_sales)               AS first_week,
    (SELECT MAX(week_end_date) FROM weekly_sales)               AS last_week,
    (SELECT COUNT(*) FROM stores)                               AS stores,
    (SELECT COUNT(DISTINCT dept_id) FROM weekly_sales)          AS departments,
    (SELECT ROUND(SUM(weekly_sales), 0) FROM weekly_sales)      AS total_sales,
    (SELECT ROUND(SUM(weekly_sales), 0) FROM weekly_sales WHERE weekly_sales < 0) AS negative_sales_total,
    (SELECT COUNT(DISTINCT month_start) FROM monthly_sales)     AS complete_months;


-- Q02: Check — monthly allocation keeps every dollar (weekly total vs monthly total, same period)
SELECT
    ROUND((SELECT SUM(w.weekly_sales * (
              SELECT COUNT(*) FROM calendar c
              WHERE c.week_end_date = w.week_end_date
                AND c.date BETWEEN '2010-02-01' AND '2012-09-30') / 7.0)
           FROM weekly_sales w), 0)                                AS weekly_sales_in_period,
    ROUND((SELECT SUM(revenue) FROM monthly_sales), 0)             AS monthly_sales_total;


-- Q03: Monthly revenue trend with year-over-year growth
SELECT
    month_start, fiscal_year, fiscal_month, month_name,
    ROUND(revenue, 0)                                                    AS revenue,
    ROUND(LAG(revenue, 12) OVER (ORDER BY month_start), 0)               AS revenue_last_year,
    ROUND(100.0 * (revenue / LAG(revenue, 12) OVER (ORDER BY month_start) - 1), 2) AS yoy_growth_pct
FROM vw_monthly_total
ORDER BY month_start;


-- Q04: Fiscal year totals (FY2013 is Feb - Sep only so far)
SELECT
    fiscal_year,
    COUNT(*)                        AS months,
    ROUND(SUM(revenue), 0)          AS revenue,
    ROUND(AVG(revenue), 0)          AS avg_month
FROM vw_monthly_total
GROUP BY fiscal_year
ORDER BY fiscal_year;


-- Q05: Same-period growth — FY2013 Feb-Sep vs FY2012 Feb-Sep
SELECT
    ROUND(SUM(CASE WHEN fiscal_year = 2012 AND fiscal_month <= 8 THEN revenue END), 0) AS fy2012_feb_sep,
    ROUND(SUM(CASE WHEN fiscal_year = 2013 AND fiscal_month <= 8 THEN revenue END), 0) AS fy2013_feb_sep,
    ROUND(100.0 * (SUM(CASE WHEN fiscal_year = 2013 AND fiscal_month <= 8 THEN revenue END)
                 / SUM(CASE WHEN fiscal_year = 2012 AND fiscal_month <= 8 THEN revenue END) - 1), 2) AS growth_pct
FROM vw_monthly_total;


-- Q06: Seasonality — each fiscal month's share of the year (complete years FY2011 & FY2012)
WITH fy AS (
    SELECT fiscal_year, fiscal_month, month_name, revenue,
           revenue / SUM(revenue) OVER (PARTITION BY fiscal_year) * 12 AS seasonal_index
    FROM vw_monthly_total
    WHERE fiscal_year IN (2011, 2012)
)
SELECT
    fiscal_month, month_name,
    ROUND(AVG(seasonal_index), 3)                AS avg_seasonal_index,   -- 1.000 = average month
    ROUND(MIN(seasonal_index), 3)                AS min_index,
    ROUND(MAX(seasonal_index), 3)                AS max_index
FROM fy
GROUP BY fiscal_month, month_name
ORDER BY fiscal_month;


-- Q07: Holiday weeks vs normal weeks (company total weekly sales)
WITH wk AS (
    SELECT week_end_date, MAX(is_holiday) AS is_holiday, SUM(weekly_sales) AS sales
    FROM weekly_sales GROUP BY week_end_date
)
SELECT
    CASE WHEN is_holiday = 1 THEN 'Holiday week' ELSE 'Normal week' END AS week_type,
    COUNT(*)                         AS weeks,
    ROUND(AVG(sales), 0)             AS avg_weekly_sales,
    ROUND(MAX(sales), 0)             AS best_week
FROM wk
GROUP BY is_holiday;


-- Q08: The five biggest weeks of the period
SELECT week_end_date, ROUND(SUM(weekly_sales), 0) AS sales, MAX(is_holiday) AS flagged_holiday
FROM weekly_sales
GROUP BY week_end_date
ORDER BY sales DESC
LIMIT 5;


-- Q09: Store types — size, revenue and productivity (FY2012, last complete year)
SELECT
    s.store_type,
    COUNT(DISTINCT s.store_id)                                   AS stores,
    ROUND(AVG(s.size_sqft), 0)                                   AS avg_size_sqft,
    ROUND(SUM(m.revenue), 0)                                     AS fy2012_revenue,
    ROUND(100.0 * SUM(m.revenue) / (SELECT SUM(revenue) FROM monthly_sales WHERE fiscal_year = 2012), 1) AS revenue_share_pct,
    ROUND(SUM(m.revenue) / COUNT(DISTINCT s.store_id), 0)        AS revenue_per_store,
    ROUND(SUM(m.revenue) / (SELECT SUM(s2.size_sqft) FROM stores s2
                            WHERE s2.store_type = s.store_type), 0) AS revenue_per_sqft
FROM monthly_sales m
JOIN stores s ON s.store_id = m.store_id
WHERE m.fiscal_year = 2012
GROUP BY s.store_type
ORDER BY s.store_type;


-- Q10: Store ranking — FY2012 revenue, revenue per sq ft and growth vs FY2011
WITH fy AS (
    SELECT store_id,
           SUM(CASE WHEN fiscal_year = 2011 THEN revenue END) AS fy2011,
           SUM(CASE WHEN fiscal_year = 2012 THEN revenue END) AS fy2012
    FROM vw_monthly_store GROUP BY store_id
)
SELECT
    f.store_id, s.store_type, s.size_sqft,
    ROUND(f.fy2012, 0)                                   AS fy2012_revenue,
    ROUND(f.fy2012 / s.size_sqft, 0)                     AS revenue_per_sqft,
    ROUND(100.0 * (f.fy2012 / f.fy2011 - 1), 2)          AS growth_vs_fy2011_pct,
    RANK() OVER (ORDER BY f.fy2012 DESC)                 AS revenue_rank,
    RANK() OVER (ORDER BY f.fy2012 / f.fy2011 DESC)      AS growth_rank
FROM fy f
JOIN stores s ON s.store_id = f.store_id
ORDER BY revenue_rank;


-- Q11: Department Pareto — how few departments make most of the revenue? (FY2012)
WITH d AS (
    SELECT dept_id, SUM(revenue) AS revenue
    FROM monthly_sales WHERE fiscal_year = 2012 GROUP BY dept_id
)
SELECT
    dept_id,
    ROUND(revenue, 0)                                                      AS fy2012_revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)                       AS share_pct,
    ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_share_pct,
    ROW_NUMBER() OVER (ORDER BY revenue DESC)                              AS rank
FROM d
ORDER BY revenue DESC
LIMIT 20;


-- Q12: BUDGET vs ACTUAL — FY2013 year to date (Feb - Sep 2012)
SELECT
    ROUND(SUM(budget), 0)                                     AS ytd_budget,
    ROUND(SUM(actual), 0)                                     AS ytd_actual,
    ROUND(SUM(actual) - SUM(budget), 0)                       AS ytd_variance,
    ROUND(100.0 * (SUM(actual) - SUM(budget)) / SUM(budget), 2) AS ytd_variance_pct,
    (SELECT ROUND(SUM(budget_amount), 0) FROM budget)         AS full_year_budget
FROM vw_bva_store_month
WHERE actual IS NOT NULL;


-- Q13: BUDGET vs ACTUAL by month, with running year-to-date variance
SELECT
    month_start, fiscal_month,
    ROUND(budget, 0)                                                        AS budget,
    ROUND(actual, 0)                                                        AS actual,
    ROUND(variance, 0)                                                      AS variance,
    ROUND(100.0 * variance_pct, 2)                                          AS variance_pct,
    CASE WHEN variance >= 0 THEN 'Favourable' ELSE 'Unfavourable' END       AS status,
    ROUND(SUM(variance) OVER (ORDER BY month_start), 0)                     AS ytd_variance
FROM vw_bva_month
WHERE actual IS NOT NULL
ORDER BY month_start;


-- Q14: BUDGET vs ACTUAL by store type (YTD)
SELECT
    store_type,
    COUNT(DISTINCT store_id)                                    AS stores,
    ROUND(SUM(budget), 0)                                       AS ytd_budget,
    ROUND(SUM(actual), 0)                                       AS ytd_actual,
    ROUND(SUM(actual) - SUM(budget), 0)                         AS variance,
    ROUND(100.0 * (SUM(actual) - SUM(budget)) / SUM(budget), 2) AS variance_pct,
    (SELECT 100.0 * growth_target FROM budget_assumptions a WHERE a.store_type = v.store_type) AS growth_target_pct
FROM vw_bva_store_month v
WHERE actual IS NOT NULL
GROUP BY store_type
ORDER BY store_type;


-- Q15: Stores furthest from budget (YTD) — best and worst 8
WITH st AS (
    SELECT store_id, store_type, SUM(budget) AS budget, SUM(actual) AS actual
    FROM vw_bva_store_month WHERE actual IS NOT NULL
    GROUP BY store_id, store_type
), ranked AS (
    SELECT st.*, actual - budget AS variance, (actual - budget) / budget AS variance_pct,
           RANK() OVER (ORDER BY (actual - budget) / budget)      AS worst_rank,
           RANK() OVER (ORDER BY (actual - budget) / budget DESC) AS best_rank
    FROM st
)
SELECT
    CASE WHEN worst_rank <= 8 THEN 'Most behind budget' ELSE 'Most ahead of budget' END AS grp,
    store_id, store_type,
    ROUND(budget, 0) AS ytd_budget, ROUND(actual, 0) AS ytd_actual,
    ROUND(variance, 0) AS variance, ROUND(100.0 * variance_pct, 2) AS variance_pct
FROM ranked
WHERE worst_rank <= 8 OR best_rank <= 8
ORDER BY variance_pct;


-- Q16: How many stores are on / off budget?
WITH st AS (
    SELECT store_id, (SUM(actual) - SUM(budget)) / SUM(budget) AS v
    FROM vw_bva_store_month WHERE actual IS NOT NULL GROUP BY store_id
)
SELECT
    CASE WHEN v >= 0      THEN '1. At or above budget'
         WHEN v >= -0.02  THEN '2. 0-2% below'
         WHEN v >= -0.05  THEN '3. 2-5% below'
         ELSE                  '4. More than 5% below' END AS band,
    COUNT(*) AS stores
FROM st
GROUP BY band
ORDER BY band;


-- Q17: Which departments explain the variance? (largest $ gaps, YTD)
WITH b AS (SELECT dept_id, SUM(budget_amount) AS budget FROM budget WHERE month_start <= '2012-09-01' GROUP BY dept_id),
     a AS (SELECT dept_id, SUM(revenue) AS actual FROM monthly_sales WHERE fiscal_year = 2013 GROUP BY dept_id)
SELECT
    COALESCE(b.dept_id, a.dept_id)                                AS dept_id,
    ROUND(COALESCE(b.budget, 0), 0)                               AS ytd_budget,
    ROUND(COALESCE(a.actual, 0), 0)                               AS ytd_actual,
    ROUND(COALESCE(a.actual, 0) - COALESCE(b.budget, 0), 0)       AS variance,
    ROUND(100.0 * (COALESCE(a.actual, 0) - COALESCE(b.budget, 0)) / NULLIF(b.budget, 0), 1) AS variance_pct
FROM b
LEFT JOIN a ON a.dept_id = b.dept_id
ORDER BY ABS(COALESCE(a.actual, 0) - COALESCE(b.budget, 0)) DESC
LIMIT 12;


-- Q18: Promotions — do bigger markdown weeks sell more? Each store is compared with itself:
--      its weeks are split into 4 equal groups by markdown spend (NTILE), and sales are shown
--      as an index vs that store's own average (1.00 = normal week). Non-holiday weeks,
--      Nov 2011 onward (when markdown data exists).
WITH wk AS (
    SELECT f.store_id, f.week_end_date, f.total_markdown, SUM(w.weekly_sales) AS sales
    FROM store_week_features f
    JOIN weekly_sales w ON w.store_id = f.store_id AND w.week_end_date = f.week_end_date
    WHERE f.week_end_date >= '2011-11-11' AND f.is_holiday = 0
      AND f.total_markdown IS NOT NULL
    GROUP BY f.store_id, f.week_end_date, f.total_markdown
), scored AS (
    SELECT *,
           NTILE(4) OVER (PARTITION BY store_id ORDER BY total_markdown)  AS markdown_quartile,
           sales / AVG(sales) OVER (PARTITION BY store_id)                AS sales_index
    FROM wk
)
SELECT
    markdown_quartile,
    CASE markdown_quartile WHEN 1 THEN 'Lowest markdowns' WHEN 4 THEN 'Highest markdowns' ELSE 'Middle' END AS label,
    COUNT(*)                          AS store_weeks,
    ROUND(AVG(total_markdown), 0)     AS avg_markdown,
    ROUND(AVG(sales_index), 3)        AS avg_sales_index
FROM scored
GROUP BY markdown_quartile
ORDER BY markdown_quartile;


-- Q19: Economic context — average store-week sales by unemployment band
WITH wk AS (
    SELECT f.store_id, f.week_end_date, f.unemployment_rate, SUM(w.weekly_sales) AS sales
    FROM store_week_features f
    JOIN weekly_sales w ON w.store_id = f.store_id AND w.week_end_date = f.week_end_date
    GROUP BY f.store_id, f.week_end_date, f.unemployment_rate
)
SELECT
    CASE WHEN unemployment_rate < 6  THEN '1. under 6%'
         WHEN unemployment_rate < 8  THEN '2. 6-8%'
         WHEN unemployment_rate < 10 THEN '3. 8-10%'
         ELSE                             '4. 10%+' END AS unemployment_band,
    COUNT(DISTINCT store_id)  AS stores,
    COUNT(*)                  AS store_weeks,
    ROUND(AVG(sales), 0)      AS avg_store_week_sales
FROM wk
GROUP BY unemployment_band
ORDER BY unemployment_band;
