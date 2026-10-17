# DATA.md

Data provenance, licensing, and reproduction guide for FYP A1083.

## Policy

No licensed vendor data ships with this repository. That covers Bloomberg, Compustat/WRDS, IBES, Markit, SDC, Capital IQ, CEIC, JKP raw extracts, REALIS, Factiva and any file derived row-for-row from them, whether or not a local copy exists. The repository ships code, schema documentation and aggregated result files (strategy-level series and test statistics, not vendor rows). It ships no synthetic or generated data. All research data was accessed under Nanyang Technological University library entitlements.

Every figure in REPORT_FINAL.md was computed on the real data described below; VERIFICATION_LEDGER.md traces each number to its executed source.

## Sources

### Bloomberg Terminal (NTU campus)

**Workbook `bloombergapi4_fixed.xlsm`** (does not ship). 30 STI constituents, monthly, 2001-01 to 2026-01, 7,891 security-months. Sheets: PriceData (PX_LAST, TOT_RETURN index, CUR_MKT_CAP, PX_TO_BOOK, EQY_DVD_YLD_IND, PX_VOLUME in horizontal blocks), Fundamentals (PE_RATIO, RETURN_COM_EQY, quarterly PX_TO_BOOK), Classification (GICS), Benchmark and RiskFree.
Provenance note: the workbook itself is genuine (IPO-ragged listing dates, verified price and market-cap paths). A legacy notebook loader once fabricated every non-price column of an exported panel via a silent ticker-hash fallback; that export and its descendants are excluded from all results (see EXCLUSIONS.md), and the shipped `code/pipeline.py` fails loudly on missing data instead. `code/FactorDataPull.bas` regenerates a clean panel from the terminal.

**Workbooks `SGX2.xlsm`, `SGX2_v4.xlsm`, `SGX3.xlsm`, `SGX3_2.xlsm`** (do not ship). SGX3 holds 76 quarterly point-in-time STI constituent snapshots (2008Q1 onward), a 366-ticker monthly panel, daily high/low and daily total-return series, and BEQS screen snapshots. SGX3_2 is the 54-ticker PIT subset used by the PIT survivorship and attribution work. SGX2/SGX2_v4 hold the 71-name blue-chip membership history (yearly and quarterly snapshots) and price/BVPS panels, built by the VBA modules in `src/`.

**Daily market series** (do not ship): SPX, VIX, DXY, FDTR, SPY workbooks.

### WRDS / Compustat Global (comp_global_daily)

Security Daily, Security Monthly, Fundamentals Annual and Quarterly, fic=SGP. 704 gvkeys raw (694 after primary-issue and currency filters), 1985 to 2026, roughly 3.26M daily rows, 338 delisted firms retained. Total returns from prccd/ajexdi x trfd. Fundamentals joined with a 4-month reporting embargo (RDQ unavailable for SGP); the event-time calibration shows roughly 24% of firm-quarters remain unpublished even at 4 months.

### IBES (tr_ibes)

Unadjusted Summary Estimates for the analyst-revision tests. Result on record: subsumed by momentum, no standalone signal.

### Markit Securities Finance Analytics (equity Asia)

Lendable inventory, indicative fees, DCBS scores. 1,443,330 daily rows, 572 SG names, 2002-05 to 2026-07, matched to 71.8% of panel name-months. Borrow-constrained results are estimated on covered names.

### SDC M&A (via WRDS)

Deal records used to classify 226 of 338 SGX delistings (SEDOL6/ISIN matching, completed deals).

### JKP Global Factor Data (contrib_global_factor)

208 factor series across 8 markets and 13 themes, used in the skew-conditional volatility-management study.

### CEIC (NTU library)

Singapore macro (IPI, PMI, CPI, NODX, USDSGD, GDP, SORA, NEER, SGS yields, M2) plus China/US/Japan series, merged to a real 1,347-row macro panel (does not ship).

### Capital IQ, REALIS, Factiva

CapIQ: designed integration, not used in any reported result. REALIS: 698,581 residential transactions, 1995 to 2025; the export lacks a developer field, so the ownership crosswalk is open work. Factiva: news extracts used to adjudicate delisting outcomes; extracts do not ship.

## File map

| Repository content | Status |
|---|---|
| `code/` (pipeline, factor model, backtest, PIT engines, canonical rerun, sensitivity scripts), `src/` (VBA data layer) | Ship |
| `results/verified/` | Ship. Aggregated result files matching VERIFICATION_LEDGER.md |
| `figures/` | Ship. 200 dpi, produced by the verified notebooks |
| All `.xlsm`/`.xlsx` vendor exports, raw panels (`panel_*`, `sg_broad_*`, `sgp_panel_*`, `membership_pit.csv`, spreads, Markit/SDC/IBES/JKP/CEIC extracts) | Never ship |
| `sql/` DuckDB files (`*.duckdb`), `sql/sources.toml`, and anything `sql/build.py --export` writes (`exports/`) | Never ship; git-ignored |
| `sql_out/`, the summaries `sql/report.py` and `sql/parity.py` write (test statistics, correlations, row counts) | May ship, like `results/verified/` |

The SQL tests (`sql/tests/`) build a few thousand rows of made-up prices in a temporary folder each time they run, purely to exercise the queries; the rows are never written into the repository and no reported number comes from them.

## Reproduction

With NTU (or equivalent) entitlements: run the VBA modules in `src/` to pull the Bloomberg workbooks, export the CEIC series, pull the WRDS files listed above, place them beside the code, and run the scripts in `code/`. Without entitlements the scripts cannot run; the result files in `results/verified/` and VERIFICATION_LEDGER.md are the evidence, and `code/make_figures.py` redraws three figures from them.
