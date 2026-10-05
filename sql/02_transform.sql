-- =====================================================================
-- 02_transform.sql — turn weekly sales into monthly revenue, then build
-- the FY2013 budget. Run after the tables are loaded.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) WEEKLY -> MONTHLY. Walmart reports Sat-Fri weeks, and many weeks
--    straddle two months. Each week's sales are spread evenly over its
--    7 days (joining to the daily calendar on week_end_date gives the 7
--    days), then summed by calendar month. This is more accurate than
--    putting the whole week in the month it ends in.
-- ---------------------------------------------------------------------
DELETE FROM monthly_sales;
INSERT INTO monthly_sales (store_id, dept_id, month_start, fiscal_year, fiscal_month, revenue)
SELECT
    w.store_id,
    w.dept_id,
    c.month_start,
    c.fiscal_year,
    c.fiscal_month,
    ROUND(SUM(w.weekly_sales / 7.0), 2) AS revenue
FROM weekly_sales w
JOIN calendar c ON c.week_end_date = w.week_end_date
GROUP BY w.store_id, w.dept_id, c.month_start, c.fiscal_year, c.fiscal_month;

-- Keep complete months only. The first week (ending 2010-02-05) starts on
-- 30 Jan 2010 and the last week ends on 26 Oct 2012, so January 2010 and
-- October 2012 are only partly covered. Complete months: Feb 2010 - Sep 2012.
DELETE FROM monthly_sales
WHERE month_start < '2010-02-01' OR month_start > '2012-09-01';

-- ---------------------------------------------------------------------
-- 2) FY2013 BUDGET = FY2012 actual for the same store, department and
--    fiscal month x (1 + growth target for the store's type).
--    Growth targets live in budget_assumptions (management assumption).
-- ---------------------------------------------------------------------
DELETE FROM budget;
INSERT INTO budget (store_id, dept_id, fiscal_year, fiscal_month, month_start, budget_amount)
SELECT
    m.store_id,
    m.dept_id,
    2013                                   AS fiscal_year,
    m.fiscal_month,
    date(m.month_start, '+1 year')         AS month_start,     -- PostgreSQL: m.month_start + INTERVAL '1 year'
    ROUND(m.revenue * (1 + a.growth_target), 2) AS budget_amount
FROM monthly_sales m
JOIN stores s             ON s.store_id   = m.store_id
JOIN budget_assumptions a ON a.store_type = s.store_type
WHERE m.fiscal_year = 2012;
