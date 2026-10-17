# Module 8. SQL research store

An independent rebuild of the broad-universe panel in SQL (DuckDB), from the raw Compustat Global extracts to canonical Tables 1 and 2, in `sql/`. The legacy panel `sg_broad_quarterly.csv` was assembled in notebooks that are not in the repository; this module writes the same pipeline as a schema whose point-in-time rules are queries rather than conventions, and checks them on every build.

What it adds: fundamentals reach a month only through an ASOF join on their embargo date; monthly windows run over a complete calendar grid, so a suspension month cannot be bridged by a return or a momentum window; forward returns are calendar-joined and never filtered by next-month membership (the double-filter trap, ledger B13, cannot be written); Markit is matched on the ISIN live in each month rather than the security's last ISIN, and the gain in matched security-months is counted. Eleven audits run on every build, seven of which must return zero rows.

Agreement with the existing code, tested on the same inputs: both Corwin-Schultz recipes match `code/cs_spreads.py` row for row; z-scores match `code/factor_model.py`; the composite matches `canonical_rerun.py`'s weighting; monthly ICs match `scipy.stats.spearmanr`; decile books match `canonical_rerun.py`'s `bt`; and the unchanged `canonical_rerun.py`, pointed at the SQL export through `SGX_PANEL`, reproduces the SQL Tables 1 and 2 to the printed digit.

It encodes the frozen main strategy (STRATEGY_FREEZE.md) as specified and changes none of it: the June-snapshot universe, the eight factors winsorised at 1% and 99% and z-scored monthly, the four-month lag, the preset weights with at least four factors, equal-weighted deciles, calendar-joined Spearman IC and NW(6) alpha. It is a reproduction, not a new specification.

Status: code and tests ship; the run on the licensed exports and the panel parity report (`sql/parity.py`, SQL build against the legacy panel and against ledger C1) are pending, so this module has no headline number yet. When it runs, its Tables 1 and 2 go into the freeze log as a reproduction check, whatever they show. Until then, results/verified/ remains the evidence for every table.

Evidence: sql/README.md; sql/tests/. Results: sql_out/parity_columns.csv and parity_table1.csv once run (summary statistics, safe to commit).
