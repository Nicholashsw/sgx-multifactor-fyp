# sgx-multifactor-fyp

A systematic multi-factor long-short equity strategy on Singapore (SGX) equities,
built as an NTU final-year project. It constructs cross-sectional factor signals,
combines them into an IC-weighted composite, and evaluates the strategy with a
walk-forward long-short backtest, Fama-MacBeth pricing tests, a BARRA-style risk
model, and a macro-regime overlay.

## Pipeline
1. **Data** (`src/pipeline.py`) — merges a Bloomberg equity panel, Capital IQ
   fundamentals, and a monthly macro panel into a clean monthly dataset. If the
   licensed exports are absent it falls back to a structurally identical synthetic
   panel so the code runs end to end.
2. **Factors** — momentum (`MOM_12_1`), value (`BM_Ratio`), quality
   (`RETURN_COM_EQY` / ROE), yield (`EQY_DVD_YLD_IND`), size (`-LogMktCap`),
   liquidity (Amihud). Each is cross-sectionally z-scored per date.
3. **Composite** — IC-weighted blend; ranked into terciles for a long-short book.
4. **Evaluation** — walk-forward L/S backtest, Fama-MacBeth with Newey-West
   standard errors, tercile monotonicity, drawdown, and a macro-regime overlay.

## VBA data layer
`src/Module1_SGX_Bloomberg.bas` and `src/Module_CapIQ_SGX.bas` pull the STI
universe and the required fields into an Excel workbook, then export CSVs that
`pipeline.py` consumes. Bloomberg fields: `TOT_RETURN_INDEX_GROSS_DVDS`,
`CUR_MKT_CAP`, `PX_TO_BOOK_RATIO`, `RETURN_ON_EQUITY`, `EQY_DVD_YLD_12M`,
`PX_VOLUME`, `BICS_LEVEL_1_SECTOR_NAME`; benchmark `STI Index`; risk-free `SGS3M`.

## Data
Bloomberg, Capital IQ, and macro-vendor exports are **licensed and not included**.
The repo ships code plus the synthetic-panel fallback. To reproduce the real
results, run the VBA export macros first, then `pipeline.py`.

## Run
```bash
pip install -r requirements.txt
python src/pipeline.py      # builds the monthly panel (synthetic if no exports)
```

## Limitations
Roughly 30-name investable universe (terciles, not quintiles); survivorship bias
(STI exits are mostly downgrades, not delistings); 45-day fundamental reporting lag
applied to avoid look-ahead; non-trivial NaN rate on P/B and ROE for some names;
deep historical drawdowns in crisis windows that argue for a volatility circuit
breaker. Results are sample-specific and not a guarantee of out-of-sample
performance.

---
*Nicholas Hong | Built for educational and research purposes. Not financial advice.*
