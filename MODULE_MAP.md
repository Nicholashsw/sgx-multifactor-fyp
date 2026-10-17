# Module map

How the ten source folders fold into one core narrative plus seven standalone modules, with an eighth (the SQL rebuild) added on top of them. Conflicts resolved by the supersession map where it speaks, otherwise by executed evidence on the more authoritative universe (liquid100 / broad Compustat > PIT roster > 30-name STI).

## Core: the factor pipeline (one merged narrative)

The single question: does a multi-factor cross-sectional model earn a robust premium on SGX? Merged from four tracks, each the latest surviving spec of its universe.

| Track | Source folders | Latest surviving spec | Headline (verified) |
|---|---|---|---|
| Broad Compustat universe (canonical for inference) | STI SGX2 (broad), FYP SGX multifactor and momentum, Sector-specific valuation, SGX multi-factor trading strategy development | canonical_rerun.py tables; 65-test specification grid; PIT eligibility with unfiltered returns | Composite IC 0.049 t=5.15 (Newey-West); survivor L/S t=1.01 vs PIT t=3.82; size-tier monotonicity; 0 of 65 grid tests survive BHY |
| Blue-chip 71-name PIT (SGX2 skeptical track) | STI SGX2 | backtest_survivorship_final.ipynb (quarterly PIT + BVPS) | IC 0.0697 t=5.90; naive Sharpe 1.002 → corrected 0.447 |
| STI-core top-6 (SGX3 track) | SGX3 | CANONICAL_METHODOLOGY spec, corrected benchmark and deciles | +0.396%/mo NW-t 2.26; Compustat reproduction +0.36 t=2.26; risk characterisation suite |
| 30-name diagnostic | SGX performance audit, SGX multi-factor FYP | SGX_Strategy_Audit.ipynb (price-only, field-gated) | No signal |t|>1.96 on clean fields; L/S diversifier hypothesis |

Merge rules applied: benchmark = investable cohort at t (Bench B) everywhere; forward returns by explicit PIT lookup; 4-month embargo stated as convention; equal weight default with the cap bug disclosed; multiple-testing verdicts quoted per test.

## Module 1. Survivorship methodology study

Folders: FYP SGX multifactor and momentum (decomposition, adjudication), STI SGX2 (strategy-level), Sector-specific valuation (leg symmetry). Finding: the bias runs backwards (−0.89 pp/yr, exit mix 59% takeouts), direction identified, magnitude an upper bound pending terminal-return adjudication; strategy-level effect is large on survivor-defined books (Sharpe 1.002→0.447) and near-symmetric across L/S legs on the PIT roster (−5.43/+5.26 pp/yr).

## Module 2. Cost and capacity waterfall

Folders: STI SGX2 (definitive waterfall), SGX multi-factor trading strategy development (spreads, borrow, execution lag), SGX3 (Markit borrow, capacity). Finding: gross 1.661%/mo t=5.13 → 0.366 t=1.08 fully costed (traded-days spreads on traded names; 0.06 to 0.54 across cost conventions); Corwin-Schultz spreads dominate (0.741%/mo); long-only cannot pay its spreads (0.09%/mo); availability, not fees, binds the short side; long-only 0.713%/mo Sharpe 0.85 is the dominant implementable form on the price-signal book; STI-core capacity ~S$50M feasibility-bound.

## Module 3. TSMOM

Folder: TSMOM. Standalone: liquid100 k=3 Sharpe 0.974 t=4.65 (survivorship-clean), horizon peak h=3-5, searched cell priced. The module finding: combination with the fundamental sleeve reverses under borrow constraints (correlation −0.14 → +0.33; combo 0.460 < TSMOM 0.543). Not flattened into the core pipeline.

## Module 4. Jump-diffusion and regime risk measurement

Folder: SGX3 (+ results appendix). A null for alpha (8 overlays, 8 fails; smoothed-probability and GARCH look-ahead traps), real for risk (57.9% jump variance share; Gaussian understates 99% ES by 1.60pp; GJR-GARCH-skewt the only conditional VaR model passing both backtests). Open benchmark: inverse-realised-vol scaling.

## Module 5. Skew-conditional volatility management

Folder: SGX momentum. Overlay benefit real ex post and skew-conditional across 208 JKP series; unexploitable ex ante (skew R² 0.003 vs 0.25 for vol; searched gates fail White's reality check).

## Module 6. Price-signal family

Folder: SGX multi-factor trading strategy development. 52-week high vs momentum subsumption flips with share turnover; gross spread survives corrections in liquid/high-turnover names, nothing survives net of spreads; statistical finding about signal structure, not tradable alpha.

## Module 7. VBA / data tooling

Folders: STI SGX2, SGX multi-factor FYP, consolidation audit. Bloomberg pull machinery (membership history via INDX_MWEIGHT_HIST with END_DATE_OVERRIDE, price panels, publication pulls), CapIQ module, daily OHLCV, diagnostic probes. Ships as code; no results of its own.

## Module 8. SQL research store

Folder: `sql/` (new; no source folder). The broad Compustat panel rebuilt from the raw vendor extracts in DuckDB SQL, so the canonical tables no longer depend on a panel assembled in notebooks outside the repository. Point-in-time rules are enforced by the schema (ASOF joins on the embargo date, a complete calendar grid for every window, calendar-joined forward returns never filtered by next-month membership) and checked by audits on every build. Tested against the project's pandas code on identical inputs: spreads, z-scores, composite, ICs and decile books agree to 1e-9 or better. The run on the licensed exports and the parity report against the legacy panel are pending, so it has no headline number yet.

## Cross-cutting: corrections log

Thirteen verified corrections (ledger section N), spanning the synthetic fallback, two look-ahead traps, the forward-return bug, the benchmark contamination, cost-base and estimator fixes. Presented as part of the contribution.

## Folder-to-module index

| Source folder | Feeds |
|---|---|
| SGX3 | Core (STI-core track), Module 4, corrections |
| STI SGX2 | Core (broad + blue-chip tracks), Modules 1, 2, 7 |
| TSMOM | Module 3; liquid100 validation for core |
| SGX momentum | Module 5; decile-shape evidence for core |
| SGX performance audit | Core (30-name diagnostic) |
| Sector-specific valuation factors | Core (factor anatomy, alignment), Module 1 (leg symmetry), corrections (cap bug, double-filter) |
| SGX multi-factor trading strategy development | Modules 2, 6; PIT validation, placebo, multiple testing M=55 |
| SGX multi-factor FYP | Module 7; contamination map; superseded papers |
| FYP SGX multifactor and momentum | Module 1; 65-test grid; panel rebuild integrity |
| Consolidation audit | REPORT/DATA baseline, shipped code |
