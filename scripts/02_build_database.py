"""
02_build_database.py
Builds data/revenue.db (SQLite):
  sql/01_schema.sql -> load clean CSVs -> sql/02_transform.sql -> sql/03_views.sql
then runs every query in sql/04_analysis_queries.sql and saves each result
to sql/query_results/Qnn_<name>.csv.
"""
import re
import sqlite3
import time
import pandas as pd
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
CLEAN, SQL = BASE / "data" / "clean", BASE / "sql"
DB = BASE / "data" / "revenue.db"
RES = SQL / "query_results"; RES.mkdir(exist_ok=True)
for f in RES.glob("Q*.csv"):
    f.unlink()
DB.unlink(missing_ok=True)

con = sqlite3.connect(DB)
con.executescript((SQL / "01_schema.sql").read_text())
for table in ["stores", "departments", "calendar", "budget_assumptions", "weekly_sales", "store_week_features"]:
    df = pd.read_csv(CLEAN / f"{table}.csv")
    df.to_sql(table, con, if_exists="append", index=False)
    print(f"loaded {table:<20} {len(df):>8,} rows")
t = time.time()
con.executescript((SQL / "02_transform.sql").read_text())
con.executescript((SQL / "03_views.sql").read_text())
con.commit()
for tbl in ["monthly_sales", "budget"]:
    print(f"built  {tbl:<20} {con.execute(f'SELECT COUNT(*) FROM {tbl}').fetchone()[0]:>8,} rows")
print(f"transform took {time.time() - t:.1f}s")

text = (SQL / "04_analysis_queries.sql").read_text()
for block in re.split(r"\n(?=-- Q\d\d:)", text)[1:]:
    title = block.splitlines()[0].replace("-- ", "")
    qid = title.split(":")[0]
    slug = re.sub(r"[^a-z0-9]+", "_", title.split(":", 1)[1].lower()).strip("_")[:45]
    df = pd.read_sql(block, con)
    df.to_csv(RES / f"{qid}_{slug}.csv", index=False)
    print(f"\n{title}\n{df.to_string(index=False)}")
con.execute("VACUUM")
con.close()
