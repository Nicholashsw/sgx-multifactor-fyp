# Code

The scripts here come from different stages of the project, so they do not form one pipeline. None of them ship with data: each one expects the licensed export named at the top of the file (see [DATA.md](../DATA.md)).

## Which script backs which result

| Result | Ledger | Script | Output |
|---|---|---|---|
| Broad-universe ICs, survivorship reversal of the long-short, size tiers, composite weighting check | C1, B11, C3, C13 | `canonical_rerun.py` | `results/verified/canonical_table1.csv` to `canonical_table4.csv`, `canonical_results.json` |
| Sector-neutral test, Brinson-Fachler, 12% vol target, cost break-even | C7r | `finish.py` | `results/verified/finish_output.txt` |
| Cost waterfall, 1.661 to 0.366%/mo, the published 0.282 version, each weighting scheme and the long-only book | D1, D1c, C13 | `cs_spreads.py` (spread files from Compustat daily), then `waterfall.py` | `results/verified/waterfall_definitive.csv`, `waterfall_schemes.csv`, `waterfall_schemes_traded_days.csv` |
| Survivorship bias of −0.89 pp/yr and its bracket down to −0.40 | B1, B6a, B7r | `survivorship_sensitivity.py` (replicates the baseline first) | `results/verified/survivorship_sensitivity_output.txt` |
| Blue-chip survivorship pair, Sharpe 1.002 to 0.447 | B9 | `../notebooks/backtest_survivorship_final.ipynb` | `results/verified/survivorship_summary_final.csv` |
| 30-name diagnostic track | REPORT_FINAL section 11 | `pipeline.py`, then `factor_model.py`, then `backtest.py` | written to the working folder, not shipped |

## Results whose notebooks are not in this repository

These headline numbers came from research notebooks that do not ship. Their result files are in `results/verified/` and each is traced in the ledger.

| Result | Ledger | Result file |
|---|---|---|
| Markit long-short, +0.764%/mo at S$50m | D7 | `ls_markit.csv`, `borrow_markit.csv` |
| STI-core strategy, +0.396%/mo, and the Compustat reproduction | E1, E3 | `sti_core_returns.csv`, `compustat_backtest_quarterly.csv` |
| Reference Table I re-derivation | E2 | `rederived_table1_fm.csv`, `rederived_table1_fm_multivariate.csv` |
| 65-test specification grid | G1 | `spec_results_N65.csv`, `spec_results_full.csv` |
| Jump risk and the overlay tests | L1, E21 | `jumpmodel_test_a.json`, `jumpmodel_test_b.json`, `jump_sizing_results.csv`, `garch_model_comparison.csv`, `ms_sizing_results.csv` |
| STI-core attribution and leakage | E4, E8, E9, E11 | `attribution/` (see its README) |

## Supporting code

- `pit_build.py`, `pit_engine.py`: functions for building the point-in-time STI panel from the Bloomberg workbook, and for running portfolios that take eligibility at formation but returns from the unfiltered panel (the double-filter fix, ledger B13). Neither has an entry point of its own.
- `pit_panel_build.py`: builds the monthly point-in-time price panel and daily-high-based 52-week highs used in the price-signal work (REPORT_FINAL section 9.2).
- `attribution.py`: attribution and leakage framework on the 30-name Bloomberg STI panel. The panel holds current members only, so spreads, borrow and delisting effects cannot be computed on it.
- `make_figures.py`: redraws the cost waterfall, the 65-test grid and the Table I chart from `results/verified/`. Needs no licensed data.
- `FactorDataPull.bas`: Bloomberg VBA pulls for the 30-name workbook.

`canonical_rerun.py` and `waterfall.py` read the panel named by `SGX_PANEL` when it is set, so they run unchanged on the panel `sql/build.py --export` rebuilds from the raw Compustat extracts (see `sql/README.md`).
