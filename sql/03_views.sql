-- =====================================================================
-- 03_views.sql — reporting views used by the queries, Python, Excel and
-- Power BI.
-- =====================================================================

-- Monthly revenue by store (all departments)
DROP VIEW IF EXISTS vw_monthly_store;
CREATE VIEW vw_monthly_store AS
SELECT
    m.store_id, s.store_type, s.size_sqft,
    m.month_start, m.fiscal_year, m.fiscal_month,
    SUM(m.revenue) AS revenue
FROM monthly_sales m
JOIN stores s ON s.store_id = m.store_id
GROUP BY m.store_id, s.store_type, s.size_sqft, m.month_start, m.fiscal_year, m.fiscal_month;

-- Company total revenue by month
DROP VIEW IF EXISTS vw_monthly_total;
CREATE VIEW vw_monthly_total AS
SELECT
    month_start, fiscal_year, fiscal_month,
    CASE fiscal_month WHEN 1 THEN 'Feb' WHEN 2 THEN 'Mar' WHEN 3 THEN 'Apr' WHEN 4 THEN 'May'
         WHEN 5 THEN 'Jun' WHEN 6 THEN 'Jul' WHEN 7 THEN 'Aug' WHEN 8 THEN 'Sep' WHEN 9 THEN 'Oct'
         WHEN 10 THEN 'Nov' WHEN 11 THEN 'Dec' ELSE 'Jan' END AS month_name,
    SUM(revenue) AS revenue
FROM monthly_sales
GROUP BY month_start, fiscal_year, fiscal_month;

-- FY2013 budget vs actual by store and month (actuals exist Feb - Sep 2012)
DROP VIEW IF EXISTS vw_bva_store_month;
CREATE VIEW vw_bva_store_month AS
WITH b AS (
    SELECT store_id, month_start, fiscal_month, SUM(budget_amount) AS budget
    FROM budget GROUP BY store_id, month_start, fiscal_month
),
a AS (
    SELECT store_id, month_start, SUM(revenue) AS actual
    FROM monthly_sales WHERE fiscal_year = 2013 GROUP BY store_id, month_start
)
SELECT
    b.store_id, s.store_type, s.size_sqft, b.month_start, b.fiscal_month,
    b.budget,
    a.actual,
    a.actual - b.budget                                        AS variance,
    CASE WHEN a.actual IS NULL THEN NULL
         ELSE ROUND((a.actual - b.budget) / b.budget, 4) END   AS variance_pct,
    CASE WHEN a.actual IS NULL          THEN 'No actual yet'
         WHEN a.actual >= b.budget      THEN 'Favourable'
         ELSE                                'Unfavourable' END AS status
FROM b
JOIN stores s ON s.store_id = b.store_id
LEFT JOIN a   ON a.store_id = b.store_id AND a.month_start = b.month_start;

-- FY2013 budget vs actual, company total by month
DROP VIEW IF EXISTS vw_bva_month;
CREATE VIEW vw_bva_month AS
SELECT
    month_start, fiscal_month,
    SUM(budget)                                    AS budget,
    SUM(actual)                                    AS actual,
    SUM(actual) - SUM(CASE WHEN actual IS NOT NULL THEN budget END) AS variance,
    ROUND((SUM(actual) - SUM(CASE WHEN actual IS NOT NULL THEN budget END))
          / SUM(CASE WHEN actual IS NOT NULL THEN budget END), 4)    AS variance_pct
FROM vw_bva_store_month
GROUP BY month_start, fiscal_month;
