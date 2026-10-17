# SQL research store

A second, independent build of the broad-universe panel, written in SQL on DuckDB, from the raw Compustat Global extracts to the canonical Tables 1 and 2. The pandas panel behind `canonical_rerun.py` (`sg_broad_quarterly.csv`) was assembled in notebooks that are not in this repository; this module rebuilds it from the vendor files with every point-in-time rule written down as a query, checks itself with integrity audits, and measures how far the legacy panel agrees with it.

It is Module 8 in [MODULE_MAP.md](../MODULE_MAP.md). The write-up is [modules/08_sql_research_store.md](../modules/08_sql_research_store.md).

## What it builds

| Layer | File | Tables |
|---|---|---|
| Typed sources | `ddl/01_typed_sources.sql` | `secd`, `funda`, `fundq`, `company`, `constituents`, `bench`, `markit`, `fx` |
| Security master | `ddl/02_security_master.sql` | `security_master` (listing window, exit, primary issue), `security_ids` (ISIN/SEDOL history), `crosswalk_last` |
| Monthly panel | `ddl/03_monthly_panel.sql` | `daily` (total-return index), `month_grid`, `monthly` (returns, market cap, Amihud, dividend yield) |
| Fundamentals | `ddl/04_fundamentals_pit.sql` | `statements` (TTM from quarters, else annual), `fund_pit` (ASOF join on the embargo date, in SGD) |
| Factors | `ddl/05_factors.sql` | `signals`, `zscores` (winsorised 1/99, z-scored per date), `composite` (preset weights) |
| Universe | `ddl/06_universe.sql` | `eligible` (latest June snapshot), `survivors`, `fwd` (calendar-joined next-month return) |
| Spreads | `ddl/07_spreads.sql` | `cs_naive`, `cs_traded`, both Corwin-Schultz recipes of `code/cs_spreads.py` |
| Borrow | `ddl/08_borrow.sql` | `borrow` (Markit matched on the identifier live that month), `borrow_match_compare` |
| Exports | `ddl/09_exports.sql` | views in the column layout of the legacy CSVs |

`queries/ic.sql` and `queries/decile_book.sql` hold the Table 1 and Table 2 selection logic; `report.py` adds only the Newey-West statistics, with the same statsmodels calls as `canonical_rerun.py`.

## Rules the schema enforces

- **No look-ahead on fundamentals.** A statement is usable from the month-end four months after its period end, and monthly rows take the latest usable one through an `ASOF JOIN` on that date. The audit `fundamentals_before_available` must return zero rows.
- **Calendar-correct windows.** Every security gets a row for every calendar month from its first to its last trade, traded or not. `LAG` and `ROWS` windows over that grid always mean calendar months, so a suspension month produces NULL returns either side of it instead of a return that silently spans two months, and momentum needs all eleven months.
- **Forward returns by calendar join.** Next month's return is month m+1's row of the same security, never the next row. The audit `shift_would_skip_a_month` counts the rows where a `shift(-1)` would have borrowed a later month (the bug class behind the false U-shaped payoff in REPORT_FINAL.md section 12).
- **Eligibility at formation, returns from the unfiltered panel.** The double-filter trap (ledger B13) cannot occur: `fwd` is built without any membership filter, and `held_through_index_exit` counts the names that keep their holding-month return as they leave the index.
- **Dead names stay.** Delisted securities keep every month up to their last trade. Terminal-return adjustments are Module 1's sensitivity question and are not applied here.

## Run

```bash
pip install -r requirements.txt
cp sql/sources.example.toml sql/sources.toml        # point it at your exports; git-ignored
python sql/build.py --sources sql/sources.toml --db sgx.duckdb --export exports/
python sql/report.py --db sgx.duckdb --out sql_out/
python sql/parity.py --db sgx.duckdb --legacy code/sg_broad_quarterly.csv --out sql_out/
```

`build.py` stops on a missing required file or column and on any failed audit. `--export` writes `sg_broad_quarterly.csv`, both spread files and the crosswalk in the legacy layouts, so the unchanged pandas scripts run on the SQL build:

```bash
cd code
SGX_PANEL=../exports/sg_broad_quarterly.csv python canonical_rerun.py
SGX_PANEL=../exports/sg_broad_quarterly.csv python waterfall.py --spreads ../exports/cs_spreads_traded.csv
```

The exports and the `.duckdb` file contain vendor-derived rows. They are git-ignored and must not be committed (DATA.md).

## Tests

```bash
python -m pytest sql/tests -q
```

The tests build a store from a few thousand rows written to a temporary folder at test time (`tests/fixtures.py`; nothing is saved to the repository and no result uses them) and check two things. First, the point-in-time rules: embargo timing, the TTM rule, FX conversion, split and dividend handling, the calendar join across a suspension, a delisted name, the June snapshot switch, momentum skipping month t, Markit matching through a changed ISIN. Second, agreement with the project's pandas code on the same inputs: both spread recipes against `code/cs_spreads.py` row for row, the z-scores against `code/factor_model.py`, the composite against `canonical_rerun.py`'s `wscore`, the monthly ICs against `scipy.stats.spearmanr`, and the decile books against `canonical_rerun.py`'s `bt`, all to 1e-9 or tighter. Run on the exported fixture panel, the unchanged `canonical_rerun.py` reproduces `report.py`'s Tables 1 and 2 to the printed digit.

## What it does not settle

The legacy panel's construction is undocumented in places: whether its z-scores use the full cross-section or the eligible names, its winsorisation, its treatment of semi-annual reporters and foreign-currency filers, and its Amihud window. `parity.py` reports where the two builds agree and where they do not; it does not assume either one is right. Compustat fundamentals are as-restated, so even an exact embargo is point-in-time in timing, not in vintage.
