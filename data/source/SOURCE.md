# Data source

**Walmart Recruiting – Store Sales Forecasting** (Kaggle competition, 2014)
https://www.kaggle.com/c/walmart-recruiting-store-sales-forecasting

Real, anonymised historical sales data that Walmart released for this competition:

| File | Rows | Contents |
|---|---|---|
| `train.csv` | 421,570 | Weekly sales by store and department, 5 Feb 2010 – 26 Oct 2012 |
| `stores.csv` | 45 | Store type (A/B/C) and size in square feet |
| `features.csv` | 8,190 | Weekly temperature, fuel price, promotional markdowns, CPI, unemployment and holiday flag per store |

The files here were downloaded unchanged from a public GitHub mirror of the competition data
(github.com/vicky60629/Walmart-Store-Sales-Forecasting, folder `data/`); file sizes match the
original Kaggle release. They are used for educational, non-commercial purposes; the data belongs
to Walmart and is subject to the Kaggle competition rules.

These files are **never modified**. All cleaning happens in `scripts/01_prepare_data.py`, which
writes to `data/clean/`.
