# Cost-Adjusted Multi-Factor Stock Selection on the Singapore Exchange (NTU FYP A1083)

Does a multi-factor cross-sectional model earn a robust premium on the Singapore Exchange, a smaller and less-arbitraged market than the US venues where factor premia decay fast? Every headline number below traces to an executed notebook cell or result file on real vendor data, listed row by row in [VERIFICATION_LEDGER.md](VERIFICATION_LEDGER.md). Numbers from earlier drafts that could not be traced to executed evidence were removed and are listed in [EXCLUSIONS.md](EXCLUSIONS.md).

The answer: the Singapore market has real, correctly signed, replicable cross-sectional return structure, and its trading frictions remove it before it becomes tradeable at institutional scale. Two findings generalise beyond Singapore: survivorship bias on SGX runs in the opposite direction to the textbook prediction, and the reference literature's factor premia do not reproduce under proper multiple-testing control.

## Headline results

| Result | Number | Universe |
|---|---|---|
| Delisting survivorship bias is NEGATIVE (dead names raise returns; 59% of exits are takeouts) | −0.89 pp/yr (bracket −0.89 to −0.40 under harsh terminal-return assumptions) | 694-firm survivorship-free Compustat SGP |
| Survivorship correction reverses the broad long-short | survivor t=1.01 vs point-in-time t=3.82 | Broad Compustat, 1991–2026 |
| Result does not hinge on the factor weights | preset 1.32%/mo (t=3.82), equal 1.01 (t=3.08), walk-forward 1.72 (t=4.58) | Broad Compustat, 1991–2026 |
| Blue-chip naive backtest vs corrected | Sharpe 1.002 → 0.447 | 71-name PIT roster |
| Cost waterfall on the winning composite | gross 1.661%/mo (t=5.13) → 0.366%/mo (t=1.08) fully costed; 0.06 to 0.54 across cost conventions, never significant | Broad Compustat, 2003–2026 |
| Dominant cost | Corwin-Schultz spreads, 0.741%/mo (traded-days median half-spread 36.4 bp) | same |
| Long-only top decile after spreads | 0.09%/mo (t=0.36): the signal lives in the short leg, where borrow binds | same |
| Implementable long-short with real borrow (Markit) | +0.764%/mo (t=2.23) at S$50m AUM | top-100 |
| STI-core strategy | +0.396%/mo, NW-t 2.26; reproduces independently on Compustat at +0.36 (t=2.26) | PIT STI top-6 |
| Multiple-testing discipline | 65-test specification grid: 24 clear t=1.96, one clears t=3.0, zero survive BHY | dev window 1995–2019 |
| Reference paper's Table I | does not reproduce: 0 of 9 factors survive Bonferroni (best 2.767 vs 2.77) | PIT STI |
| Overlays (Barra, HMM, GBM, jump models, GARCH, Markov, IBES, jump sizing) | 8 tested, 8 failed to add risk-adjusted return | STI-core |
| Risk is jump-dominated | 57.9% jump variance; Gaussian understates 99% ES by 1.60pp (34%) | STI-core daily |
| TSMOM combination with fundamentals | reverses under borrow constraints (combo 0.460 < TSMOM 0.543) | liquid100 |

![Cost waterfall: gross alpha to fully costed](figures/cost_waterfall_definitive.png)

![Survivorship bias is negative in both universes](figures/surv_bias_both_universes.png)

![Leakage funnel](figures/core_leakage_funnel.png)

![Markit borrow: the availability screen does the selection work](figures/cost_markit_ls.png)

## What is where

| Path | Content |
|---|---|
| [REPORT_FINAL.md](REPORT_FINAL.md) | The research report; every number is tagged to a ledger row |
| [paper/SGX_Multifactor_Research_Report.pdf](paper/SGX_Multifactor_Research_Report.pdf) | The same report as a PDF |
| [STRATEGY_FREEZE.md](STRATEGY_FREEZE.md) | The locked strategy, the numbers at the freeze, and what counts as robustness |
| [VERIFICATION_LEDGER.md](VERIFICATION_LEDGER.md) | Claim-by-claim trace to executed evidence (VERIFIED / UNSUPPORTED / CONTAMINATED) |
| [EXCLUSIONS.md](EXCLUSIONS.md) | Everything cut from the report, and why |
| [MODULE_MAP.md](MODULE_MAP.md), `modules/` | How the research branches fit into one core result plus eight modules |
| [DATA.md](DATA.md) | Sources, licensing and reproduction routes; no licensed data ships |
| `figures/` | 46 figures at 200 dpi, all from real-data runs, indexed in [figures/README.md](figures/README.md); three are redrawn from shipped results by `code/make_figures.py` |
| `code/` | Pipeline, factor model, backtest, point-in-time engines, canonical re-runs and sensitivity scripts; [code/README.md](code/README.md) maps each headline result to the script or result file behind it |
| `src/` | VBA data layer: Bloomberg and CapIQ pulls, point-in-time index membership |
| [`sql/`](sql/README.md) | Module 8: the broad panel rebuilt in SQL (DuckDB) from the raw Compustat extracts, with point-in-time joins, build audits, Tables 1 and 2, and a parity report against the legacy panel |
| `results/verified/` | Result files behind the ledger |
| `notebooks/` | Survivorship backtest; `backtest_survivorship_final.ipynb` is the canonical quarterly point-in-time run. It ships without cell outputs, because running it needs licensed Bloomberg/Compustat panels and saved outputs would contain vendor rows. Its numbers are in `results/verified/survivorship_summary_final.csv` (ledger B1, B9, B11). |

## Reproduce

Every script runs on the licensed exports named at the top of the file, which need NTU-equivalent entitlements (Bloomberg, WRDS Compustat/IBES/Markit/SDC, CEIC, JKP); DATA.md lists the routes. With them in place:

```bash
pip install -r requirements.txt
cd code
python canonical_rerun.py   # broad-universe Tables 1 to 4
python pipeline.py          # 30-name Bloomberg panel, then
python factor_model.py
python backtest.py
python make_figures.py      # redraws three figures from results/verified/; needs no licensed data
```

Each script stops with an error if an input is missing. No script generates or falls back to made-up data. Without the licensed exports, the result files in `results/verified/` and the ledger are the evidence.

## Corrections

An early version of the pipeline fell back silently to a seeded random generator when a Bloomberg export was missing, so its outputs were fabricated. That was caught, every result downstream of it was thrown out and rebuilt on real data, and the generator was reproduced exactly to confirm the contamination. Other errors found and fixed along the way: a forward-return alignment bug that produced a false U-shaped payoff, a GARCH look-ahead that inflated Sharpe from 0.73 to 1.05, Markov smoothed probabilities worth a spurious +0.525 Sharpe, a benchmark built from t+1 index members that overstated the passive alternative by 0.395%/mo, a cost-base error behind a spurious 1,400%/month turnover figure, the Corwin-Schultz liquidity-ordering inversion, and a one-month target leak in the walk-forward of `code/backtest.py`. The research corrections are logged in REPORT_FINAL.md section 12.

Nicholas Hong, NTU EEE, supervised by Prof. Patricia Wong. Educational and research use.
