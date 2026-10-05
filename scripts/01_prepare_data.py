"""
01_prepare_data.py
Reads the original Walmart files in data/source/ (never modified), checks and
cleans them, and writes database-ready CSVs to data/clean/.

Source: Walmart Recruiting - Store Sales Forecasting (Kaggle, 2014), real
anonymised weekly sales for 45 stores, Feb 2010 - Oct 2012.
"""
import numpy as np
import pandas as pd
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
SRC, CLEAN = BASE / "data" / "source", BASE / "data" / "clean"
CLEAN.mkdir(parents=True, exist_ok=True)
log = []

def note(table, check, rows, action):
    log.append({"table": table, "check": check, "rows": int(rows), "action": action})
    print(f"[{table}] {check}: {rows:,} -> {action}")

# ---------------------------------------------------------------- stores
raw = open(SRC / "stores.csv", newline="").read()
if "\r" in raw and "\n" not in raw:
    note("stores", "File uses old Mac line endings (\\r)", 1, "converted to normal line endings")
stores = pd.read_csv(pd.io.common.StringIO(raw.replace("\r\n", "\n").replace("\r", "\n")))
stores.columns = ["store_id", "store_type", "size_sqft"]
note("stores", "Rows loaded", len(stores), "45 stores, types A/B/C")

# ---------------------------------------------------------------- weekly sales
sales = pd.read_csv(SRC / "train.csv", parse_dates=["Date"])
sales.columns = ["store_id", "dept_id", "week_end_date", "weekly_sales", "is_holiday"]
note("weekly_sales", "Rows loaded", len(sales), "one row per store x department x week")
dup = sales.duplicated(["store_id", "dept_id", "week_end_date"]).sum()
note("weekly_sales", "Duplicate store-dept-week rows", dup, "none found" if dup == 0 else "removed")
sales = sales.drop_duplicates(["store_id", "dept_id", "week_end_date"])
neg = (sales.weekly_sales < 0).sum()
note("weekly_sales", "Negative weekly sales (returns exceed sales)", neg,
     "kept - they are real returns/adjustments; flagged in column is_negative")
sales["is_negative"] = (sales.weekly_sales < 0).astype(int)
sales["is_holiday"] = sales.is_holiday.astype(int)
assert (sales.week_end_date.dt.dayofweek == 4).all()        # every week ends on a Friday
note("weekly_sales", "Week-ending day check", len(sales), "all weeks end on Friday (Sat-Fri weeks)")
assert sales.store_id.isin(stores.store_id).all()
n_weeks = sales.week_end_date.nunique()
gaps = len(stores) * sales.dept_id.nunique() * n_weeks - len(sales)
note("weekly_sales", "Store-dept-weeks with no row", gaps,
     "not every store has every department every week; treated as no sales")

# ---------------------------------------------------------------- store-week features
feat = pd.read_csv(SRC / "features.csv", parse_dates=["Date"])
feat.columns = ["store_id", "week_end_date", "temperature_f", "fuel_price", "markdown1", "markdown2",
                "markdown3", "markdown4", "markdown5", "cpi", "unemployment_rate", "is_holiday"]
feat["is_holiday"] = feat.is_holiday.astype(int)
before = len(feat)
feat = feat[feat.week_end_date <= sales.week_end_date.max()]
note("store_week_features", "Weeks after last sales week (competition test period)", before - len(feat),
     "removed - no sales to compare against")
md = [f"markdown{i}" for i in range(1, 6)]
pre = (feat.week_end_date < "2011-11-11") & feat[md].isna().all(axis=1)
note("store_week_features", "Markdown data missing before Nov 2011", pre.sum(),
     "left blank (NULL) - Walmart only provided markdowns from Nov 2011; not set to 0")
neg_md = (feat[md] < 0).sum().sum()
note("store_week_features", "Negative markdown values", neg_md, "kept as provided (small adjustments)")
feat["total_markdown"] = feat[md].sum(axis=1, min_count=1)
h = sales.drop_duplicates(["store_id", "week_end_date"])[["store_id", "week_end_date", "is_holiday"]]
chk = feat.merge(h, on=["store_id", "week_end_date"], suffixes=("", "_s"))
note("store_week_features", "Holiday flag mismatches vs sales file", (chk.is_holiday != chk.is_holiday_s).sum(),
     "none - flags agree")

# ---------------------------------------------------------------- departments
depts = pd.DataFrame({"dept_id": sorted(sales.dept_id.unique())})
depts["dept_name"] = "Dept " + depts.dept_id.astype(str).str.zfill(2)
note("departments", "Department names", len(depts),
     "Walmart anonymised departments to numbers; labelled 'Dept 01' etc.")

# ---------------------------------------------------------------- calendar (daily, Walmart fiscal year)
days = pd.DataFrame({"date": pd.date_range("2010-01-30", "2013-01-31", freq="D")})
d = days.date
days["fiscal_year"] = np.where(d.dt.month == 1, d.dt.year, d.dt.year + 1)   # FY ends 31 Jan, named by end year
days["fiscal_month"] = (d.dt.month - 2) % 12 + 1                          # Feb = 1 ... Jan = 12
days["fiscal_quarter"] = (days.fiscal_month - 1) // 3 + 1
days["month_start"] = d.dt.to_period("M").dt.to_timestamp()
days["month_name"] = d.dt.strftime("%b")
days["calendar_year"] = d.dt.year
days["calendar_month"] = d.dt.month
days["week_end_date"] = d + pd.to_timedelta((4 - d.dt.dayofweek) % 7, unit="D")   # the Friday ending its week
days["day_of_week"] = d.dt.day_name()
note("calendar", "Days generated", len(days), "Walmart fiscal year: Feb-Jan, FY2013 = Feb 2012 - Jan 2013")

# ---------------------------------------------------------------- budget assumptions (management targets)
assumptions = pd.DataFrame({
    "store_type": ["A", "B", "C"],
    "growth_target": [0.030, 0.020, 0.015],
    "rationale": ["Large supercenters - main growth driver",
                  "Mid-size stores - modest growth",
                  "Small stores - low growth"],
})
note("budget_assumptions", "FY2013 growth targets", 3,
     "ASSUMPTION (not Walmart data): budget = FY2012 actual x (1 + target)")

stores.to_csv(CLEAN / "stores.csv", index=False)
depts.to_csv(CLEAN / "departments.csv", index=False)
sales.to_csv(CLEAN / "weekly_sales.csv", index=False, date_format="%Y-%m-%d")
feat.to_csv(CLEAN / "store_week_features.csv", index=False, date_format="%Y-%m-%d")
days.to_csv(CLEAN / "calendar.csv", index=False, date_format="%Y-%m-%d")
assumptions.to_csv(CLEAN / "budget_assumptions.csv", index=False)
pd.DataFrame(log).to_csv(CLEAN / "cleaning_log.csv", index=False)
