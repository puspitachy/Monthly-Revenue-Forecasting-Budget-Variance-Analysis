-- =====================================================================
-- Monthly Revenue Forecasting & Budget Variance Analysis (Walmart data)
-- 01_schema.sql — database schema
--
-- Standard SQL; runs in SQLite and PostgreSQL as written
-- (MySQL: use DECIMAL / DATE types the same way; no changes needed).
--
--   stores 1──< weekly_sales >──1 departments
--   stores 1──< store_week_features
--   calendar (daily) maps every date to its week, month and fiscal period
--   monthly_sales  : weekly sales allocated to calendar months (built in 02)
--   budget         : FY2013 budget by store x department x month (built in 02)
--   forecast       : monthly forecasts written by the Python notebook
-- =====================================================================

DROP TABLE IF EXISTS forecast;
DROP TABLE IF EXISTS budget;
DROP TABLE IF EXISTS monthly_sales;
DROP TABLE IF EXISTS store_week_features;
DROP TABLE IF EXISTS weekly_sales;
DROP TABLE IF EXISTS budget_assumptions;
DROP TABLE IF EXISTS calendar;
DROP TABLE IF EXISTS departments;
DROP TABLE IF EXISTS stores;

CREATE TABLE stores (
    store_id     INTEGER PRIMARY KEY,
    store_type   CHAR(1) NOT NULL,          -- A = large, B = medium, C = small
    size_sqft    INTEGER NOT NULL
);

CREATE TABLE departments (
    dept_id      INTEGER PRIMARY KEY,
    dept_name    VARCHAR(20)                -- Walmart anonymised departments to numbers
);

CREATE TABLE calendar (
    date            DATE PRIMARY KEY,
    fiscal_year     INTEGER NOT NULL,       -- Walmart FY ends 31 Jan; FY2013 = Feb 2012 - Jan 2013
    fiscal_month    INTEGER NOT NULL,       -- 1 = Feb ... 12 = Jan
    fiscal_quarter  INTEGER NOT NULL,
    month_start     DATE NOT NULL,
    month_name      CHAR(3),
    calendar_year   INTEGER,
    calendar_month  INTEGER,
    week_end_date   DATE NOT NULL,          -- the Friday that ends this date's Sat-Fri week
    day_of_week     VARCHAR(10)
);

CREATE TABLE weekly_sales (
    store_id       INTEGER NOT NULL REFERENCES stores(store_id),
    dept_id        INTEGER NOT NULL REFERENCES departments(dept_id),
    week_end_date  DATE NOT NULL,
    weekly_sales   DECIMAL(12,2) NOT NULL,  -- can be negative (returns > sales)
    is_holiday     INTEGER NOT NULL,        -- Super Bowl, Labor Day, Thanksgiving, Christmas weeks
    is_negative    INTEGER NOT NULL,
    PRIMARY KEY (store_id, dept_id, week_end_date)
);

CREATE TABLE store_week_features (
    store_id           INTEGER NOT NULL REFERENCES stores(store_id),
    week_end_date      DATE NOT NULL,
    temperature_f      DECIMAL(6,2),
    fuel_price         DECIMAL(6,3),
    markdown1          DECIMAL(12,2),       -- promotional markdowns; NULL before Nov 2011
    markdown2          DECIMAL(12,2),
    markdown3          DECIMAL(12,2),
    markdown4          DECIMAL(12,2),
    markdown5          DECIMAL(12,2),
    cpi                DECIMAL(10,4),
    unemployment_rate  DECIMAL(6,3),
    is_holiday         INTEGER,
    total_markdown     DECIMAL(12,2),
    PRIMARY KEY (store_id, week_end_date)
);

CREATE TABLE budget_assumptions (
    store_type     CHAR(1) PRIMARY KEY,
    growth_target  DECIMAL(6,4) NOT NULL,   -- e.g. 0.03 = +3% vs last year
    rationale      VARCHAR(100)
);

CREATE TABLE monthly_sales (
    store_id      INTEGER NOT NULL REFERENCES stores(store_id),
    dept_id       INTEGER NOT NULL REFERENCES departments(dept_id),
    month_start   DATE NOT NULL,
    fiscal_year   INTEGER NOT NULL,
    fiscal_month  INTEGER NOT NULL,
    revenue       DECIMAL(14,2) NOT NULL,
    PRIMARY KEY (store_id, dept_id, month_start)
);

CREATE TABLE budget (
    store_id       INTEGER NOT NULL REFERENCES stores(store_id),
    dept_id        INTEGER NOT NULL REFERENCES departments(dept_id),
    fiscal_year    INTEGER NOT NULL,
    fiscal_month   INTEGER NOT NULL,
    month_start    DATE NOT NULL,
    budget_amount  DECIMAL(14,2) NOT NULL,
    PRIMARY KEY (store_id, dept_id, month_start)
);

CREATE TABLE forecast (
    level          VARCHAR(20) NOT NULL,    -- 'Total' or 'Store type' or 'Store'
    level_value    VARCHAR(20) NOT NULL,    -- e.g. 'All', 'A', '14'
    model          VARCHAR(40) NOT NULL,
    purpose        VARCHAR(20) NOT NULL,    -- 'Backtest' (vs known actuals) or 'Forecast' (future)
    month_start    DATE NOT NULL,
    forecast       DECIMAL(16,2) NOT NULL,
    lower_80       DECIMAL(16,2),
    upper_80       DECIMAL(16,2),
    PRIMARY KEY (level, level_value, model, purpose, month_start)
);

CREATE INDEX idx_ws_week   ON weekly_sales(week_end_date);
CREATE INDEX idx_cal_week  ON calendar(week_end_date);
CREATE INDEX idx_ms_month  ON monthly_sales(month_start);
CREATE INDEX idx_bud_month ON budget(month_start);
