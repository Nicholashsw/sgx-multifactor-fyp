# Results — survivorship-corrected factor study

Aggregated outputs from the point-in-time (PIT), survivorship-bias-corrected pipeline.
**No raw vendor panels are included** (those are Bloomberg-licensed and kept local).

## Point-in-time survivorship method
The original study used the *current* index constituents, which biases factor returns
upward (delisted/removed names are dropped). The corrected pipeline rebuilds the
universe as-of each date:

1. `src/PullHistoricalMembership.bas` / `src/PublicationPulls.bas` — pull as-of-date
   index membership (`INDX_MWEIGHT_HIST` + `END_DATE_OVERRIDE`), producing a
   MasterUniverse that **includes names that later left or were delisted**.
2. `src/PIT_Survivorship_v2.bas` — survivorship-free price/fundamental puller
   (auto-retry + diagnostics; supersedes the v1 macro).
3. `notebooks/backtest_survivorship.ipynb` — re-runs factor IC and the long-short
   backtest on the corrected universe.

## Files
| File | Content |
|---|---|
| `survivorship_summary.csv` | summary stats, corrected universe |
| `survivorship_comparison.csv` | corrected vs naive (survivorship-biased) side by side |
| `ic_results.csv`, `ic_results_real.csv` | factor information coefficients (naive / corrected) |
| `backtest_results.csv`, `backtest_real.csv` | long-short backtest (naive / corrected) |

Raw inputs (`panel_*`, `membership_pit.csv`) are Bloomberg-derived and are **not** redistributed.
