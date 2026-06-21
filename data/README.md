# Data — LICENSED, not shipped

The factor panel is built from **licensed** vendor data and is therefore **not committed**:

| Source | Fields / tickers | How to obtain |
|---|---|---|
| **Bloomberg** (`Module1_SGX_Bloomberg.bas`) | SGX equity prices, market cap, volume, fundamentals via BDH/BDP | Bloomberg Terminal / BQL |
| **Capital IQ** (`Module_CapIQ_SGX.bas`) | Point-in-time fundamentals, factor inputs | S&P Capital IQ |

To run without a vendor subscription, `src/simulate.py` generates a **synthetic panel** matching
the schema (same columns/factor structure) so the full pipeline is reproducible end-to-end.
No raw vendor export (`.xlsm`) is included in this repository.
