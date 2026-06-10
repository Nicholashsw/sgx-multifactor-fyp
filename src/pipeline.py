"""
SGX Multi-Factor FYP — Data Pipeline
=====================================
Merges Bloomberg, CapIQ, and a licensed macro data vendor data into a clean monthly panel.

Sources consumed:
  Bloomberg (from bloombergapi4_fixed.xlsm exports):
    PriceData.csv        — monthly: PX_LAST, TOT_RETURN, MktCap, P/B, DivYld, Volume
    Fundamentals.csv     — quarterly: PE, ROE, P/B
    Benchmark.csv        — monthly: STI + SGMCNL index levels
    RiskFree.csv         — monthly: MASB3M 3-month rate
    Universe.csv         — ticker list + sector
    Classification.csv   — GICS sector/industry

  CapIQ (from CapIQ_SGX_FYP.xlsm exports):
    CIQ_Snapshot.csv     — current LTM snapshot per ticker
    CIQ_TimeSeries.csv   — quarterly fundamentals history

  a licensed macro data vendor (direct from downloaded xlsx files):
    sti_sgx.xlsx         — SG macro (IPI, PMI, CPI, SORA, yields, NEER, M2, GDP)
    sti_sgx_2.xlsx       — SG GDP components + China IPI
    bfeus_factor.xlsx    — CN/JP/US macro factors

  Bloomberg global (daily → resampled monthly):
    SPX_INDEX.xlsx       — S&P 500 daily close
    VIX_Index.xlsx       — VIX daily
    DXY_Curncy.xlsx      — DXY daily
    FDTR_Index.xlsx      — Fed Funds target rate daily
    SPY_US_Equity.xlsx   — SPY daily

Usage:
    python pipeline.py

Output:
    panel_monthly.csv    — full merged panel, one row per ticker × month
    macro_monthly.csv    — macro factors only (one row per month)
    README_panel.txt     — column dictionary
"""

import pandas as pd
import numpy as np
from pathlib import Path
import warnings
warnings.filterwarnings("ignore")

DATA_DIR = Path(".")   # Change to wherever your CSVs live
OUT_DIR  = Path(".")

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: Load Bloomberg price/fundamental data (from xlsm CSV exports)
# ─────────────────────────────────────────────────────────────────────────────

def load_bbg_horizontal(csv_path: Path, metric_name: str) -> pd.DataFrame:
    """
    Parses the horizontal BDH layout from bloombergapi4_fixed.xlsm exports.
    Layout:
      Row 1 = metric block headers
      Row 2 = ticker names (col 1, 4, 7, ...)  [COL_STRIDE=3]
      Row 3 = 'Date' / 'FieldName' sub-headers
      Row 4+ = Date | Value pairs per ticker block
    Returns long-format DataFrame: [Date, Ticker, <metric_name>]
    """
    df_raw = pd.read_csv(csv_path, header=None)

    # Find row 2 (0-indexed row 1 after header=None) — contains tickers
    # Find row 3 — contains "Date" labels
    # Find row 4+ — actual data

    # Detect ticker row: row where values look like "XXX SP Equity"
    ticker_row = None
    for ridx in range(min(10, len(df_raw))):
        row_vals = df_raw.iloc[ridx].dropna().astype(str)
        sp_count = sum(1 for v in row_vals if " SP " in v or "Equity" in v)
        if sp_count >= 3:
            ticker_row = ridx
            break

    if ticker_row is None:
        print(f"  Warning: could not find ticker row in {csv_path.name}")
        return pd.DataFrame()

    # Data starts 2 rows after ticker row (skip sub-header row)
    data_start = ticker_row + 2

    # Extract tickers and their column positions
    ticker_cols = {}
    for cidx, val in enumerate(df_raw.iloc[ticker_row]):
        if pd.notna(val) and (" SP " in str(val) or "Equity" in str(val)):
            ticker_cols[cidx] = str(val).strip()

    frames = []
    for date_col, ticker in ticker_cols.items():
        val_col = date_col + 1
        if val_col >= len(df_raw.columns):
            continue

        sub = df_raw.iloc[data_start:, [date_col, val_col]].copy()
        sub.columns = ["Date", metric_name]
        sub["Date"] = pd.to_datetime(sub["Date"], errors="coerce")
        sub[metric_name] = pd.to_numeric(sub[metric_name], errors="coerce")
        sub = sub.dropna(subset=["Date"])
        sub["Ticker"] = ticker
        frames.append(sub[["Date", "Ticker", metric_name]])

    if not frames:
        return pd.DataFrame()

    return pd.concat(frames, ignore_index=True)


def load_bloomberg_price_panel(csv_dir: Path) -> pd.DataFrame:
    """Load all Bloomberg price metrics and merge into one long panel."""
    price_csv = csv_dir / "PriceData.csv"
    fund_csv  = csv_dir / "Fundamentals.csv"

    if not price_csv.exists():
        print(f"  PriceData.csv not found in {csv_dir}")
        return pd.DataFrame()

    # Each metric block in the CSV needs separate parsing
    # For now: read the raw CSV and reconstruct per metric
    # The horizontal layout stores 6 metrics with stride 3 per ticker
    # Metric order: PX_LAST, TOT_RETURN_INDEX_GROSS_DVDS, CUR_MKT_CAP,
    #               PX_TO_BOOK_RATIO, EQY_DVD_YLD_IND, PX_VOLUME

    df_raw = pd.read_csv(price_csv, header=None)

    # Find metric block headers in row 0 (row 1 of Excel)
    row0 = df_raw.iloc[0].fillna("").astype(str)
    metric_start_cols = {}
    metric_map = {
        "Price (Last)": "PX_LAST",
        "Total Return Index": "TOT_RETURN",
        "Mkt Cap": "MKT_CAP_SGDmn",
        "P/B Ratio": "PX_TO_BOOK",
        "Div Yield": "DIV_YIELD",
        "Volume": "PX_VOLUME",
    }
    for cidx, val in enumerate(row0):
        for label, metric in metric_map.items():
            if label.lower() in val.lower():
                metric_start_cols[cidx] = metric
                break

    frames = []
    for block_col, metric in metric_start_cols.items():
        # Ticker row is row index 1 (Excel row 2), data from row index 3 (Excel row 4)
        ticker_row_idx = 1
        data_start_idx = 3

        # Scan columns from block_col until next block
        next_block = min(
            [c for c in metric_start_cols if c > block_col],
            default=len(df_raw.columns)
        )

        col_range = range(block_col, next_block)
        for cidx in col_range:
            ticker_val = str(df_raw.iloc[ticker_row_idx, cidx]) if cidx < len(df_raw.columns) else ""
            if " SP " not in ticker_val and "Equity" not in ticker_val:
                continue
            val_col = cidx + 1
            if val_col >= len(df_raw.columns):
                continue

            sub = df_raw.iloc[data_start_idx:, [cidx, val_col]].copy()
            sub.columns = ["Date", metric]
            sub["Date"] = pd.to_datetime(sub["Date"], errors="coerce")
            sub[metric] = pd.to_numeric(sub[metric], errors="coerce")
            sub = sub.dropna(subset=["Date"])
            sub["Ticker"] = ticker_val.strip()
            frames.append(sub[["Date", "Ticker", metric]])

    if not frames:
        return pd.DataFrame()

    merged = frames[0]
    for f in frames[1:]:
        merged = pd.merge(merged, f, on=["Date", "Ticker"], how="outer")

    return merged.sort_values(["Ticker", "Date"]).reset_index(drop=True)


def load_bloomberg_benchmark(csv_dir: Path) -> pd.DataFrame:
    """Load STI and SGMCNL benchmark from Benchmark.csv."""
    path = csv_dir / "Benchmark.csv"
    if not path.exists():
        return pd.DataFrame()

    df = pd.read_csv(path, header=None)
    # Layout: Date_STI in col 0, STI_PX_LAST in col 1, gap col 2, Date_SGMCNL col 3, SGMCNL col 4

    # Find data start
    data_rows = []
    for i in range(len(df)):
        try:
            d = pd.to_datetime(df.iloc[i, 0])
            data_rows.append(i)
        except:
            pass

    if not data_rows:
        return pd.DataFrame()

    dstart = data_rows[0]
    sub = df.iloc[dstart:].copy()

    result = pd.DataFrame()
    result["Date"] = pd.to_datetime(sub.iloc[:, 0], errors="coerce")
    result["STI_PX_LAST"] = pd.to_numeric(sub.iloc[:, 1], errors="coerce")
    if sub.shape[1] > 4:
        sgmc_dates = pd.to_datetime(sub.iloc[:, 3], errors="coerce")
        sgmc_vals  = pd.to_numeric(sub.iloc[:, 4], errors="coerce")
        sgmc_df = pd.DataFrame({"Date": sgmc_dates, "SGMCNL_PX_LAST": sgmc_vals})
        result = pd.merge(result, sgmc_df, on="Date", how="left")

    result = result.dropna(subset=["Date"]).sort_values("Date").reset_index(drop=True)

    # Add monthly returns
    result = result.sort_values("Date")
    result["STI_Return_1M"] = result["STI_PX_LAST"].pct_change()
    if "SGMCNL_PX_LAST" in result.columns:
        result["SGMCNL_Return_1M"] = result["SGMCNL_PX_LAST"].pct_change()

    return result


def load_risk_free(csv_dir: Path) -> pd.DataFrame:
    """Load risk-free rate from RiskFree.csv."""
    path = csv_dir / "RiskFree.csv"
    if not path.exists():
        return pd.DataFrame()

    df = pd.read_csv(path, header=None)
    # Col 0 = Date, Col 1 = Rate
    data_rows = []
    for i in range(len(df)):
        try:
            pd.to_datetime(df.iloc[i, 0])
            data_rows.append(i)
        except:
            pass

    if not data_rows:
        return pd.DataFrame()

    sub = df.iloc[data_rows[0]:].copy()
    result = pd.DataFrame()
    result["Date"] = pd.to_datetime(sub.iloc[:, 0], errors="coerce")
    result["RiskFree_3M"] = pd.to_numeric(sub.iloc[:, 1], errors="coerce")
    result["RiskFree_Monthly"] = result["RiskFree_3M"] / 100 / 12

    return result.dropna(subset=["Date"]).sort_values("Date").reset_index(drop=True)


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: Load Bloomberg global market factors (daily → monthly)
# ─────────────────────────────────────────────────────────────────────────────

def load_bbg_daily(path: Path, col_name: str) -> pd.DataFrame:
    """Load a Bloomberg single-series daily export and return as monthly end-of-month."""
    df = pd.read_csv(path) if str(path).endswith('.csv') else pd.read_excel(path)

    # Bloomberg layout: rows 0-3 are metadata, row 4+ is data
    data_col = [c for c in df.columns if "Unnamed" not in str(c) and c != "Security"][0]
    data_rows = []
    for i, row in df.iterrows():
        try:
            d = pd.to_datetime(row["Security"])
            v = pd.to_numeric(row[data_col], errors="coerce")
            data_rows.append({"Date": d, col_name: v})
        except:
            pass

    if not data_rows:
        return pd.DataFrame()

    daily = pd.DataFrame(data_rows).set_index("Date").sort_index()
    monthly = daily.resample("ME").last()
    monthly.index.name = "Date"
    monthly = monthly.reset_index()
    monthly[col_name] = pd.to_numeric(monthly[col_name], errors="coerce")
    return monthly


def build_market_factors(data_dir: Path) -> pd.DataFrame:
    """Merge SPX, VIX, DXY, FDTR, SPY into monthly macro factors table."""
    series = {
        "SPX_INDEX.xlsx": "SPX_Close",
        "VIX_Index.xlsx": "VIX_MonthEnd",
        "DXY_Curncy.xlsx": "DXY_MonthEnd",
        "FDTR_Index.xlsx": "FDTR_MonthEnd",
        "SPY_US_Equity.xlsx": "SPY_Close",
    }

    frames = []
    for fname, col in series.items():
        fpath = data_dir / fname
        if fpath.exists():
            df = load_bbg_daily(fpath, col)
            frames.append(df)
            print(f"  Loaded {fname}: {len(df)} months")
        else:
            print(f"  {fname} not found — skipping")

    if not frames:
        return pd.DataFrame()

    merged = frames[0]
    for f in frames[1:]:
        merged = pd.merge(merged, f, on="Date", how="outer")

    merged = merged.sort_values("Date").reset_index(drop=True)

    # Add momentum returns
    for col in ["SPX_Close", "SPY_Close"]:
        if col in merged.columns:
            ret_col = col.replace("Close", "Ret_1M")
            merged[ret_col] = merged[col].pct_change()

    # VIX 3-month rolling average (regime filter)
    if "VIX_MonthEnd" in merged.columns:
        merged["VIX_3M_Avg"] = merged["VIX_MonthEnd"].rolling(3, min_periods=1).mean()

    # Yield curve proxy: 10Y - 2Y spread (from a licensed macro data vendor, added in macro section)
    return merged


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: Load a licensed macro data vendor macro data
# ─────────────────────────────────────────────────────────────────────────────

def parse_ceic_file(path: Path) -> tuple[pd.DataFrame, list]:
    """Parse a a licensed macro data vendor Excel export. Returns (data_df, series_names)."""
    df = pd.read_excel(path, sheet_name=0, header=None)

    # Find where data starts (col 0 becomes a date)
    data_start = None
    for i in range(len(df)):
        try:
            pd.to_datetime(df.iloc[i, 0])
            data_start = i
            break
        except:
            pass

    if data_start is None:
        return pd.DataFrame(), []

    series_names = list(df.iloc[0, 1:])  # Row 0 = series names
    data = df.iloc[data_start:].copy()
    data.columns = ["Date"] + list(range(1, len(data.columns)))
    data["Date"] = pd.to_datetime(data["Date"], errors="coerce")
    data = data.dropna(subset=["Date"]).set_index("Date").sort_index()

    for c in data.columns:
        data[c] = pd.to_numeric(data[c], errors="coerce")

    return data, series_names


def build_sg_macro(data_dir: Path) -> pd.DataFrame:
    """Build Singapore macro panel from a licensed macro data vendor files."""
    # sti_sgx.xlsx: 14 SG + global series
    sg_data, sg_names = parse_ceic_file(data_dir / "sti_sgx.xlsx")
    # sti_sgx_2.xlsx: SG GDP components + China IPI
    sg2_data, sg2_names = parse_ceic_file(data_dir / "sti_sgx_2.xlsx")

    col_map_sg = {
        0: "SG_IPI_Mfg",
        1: "SG_PMI_Mfg",
        2: "SG_CPI_YoY",
        3: "SG_NODX_Electronics",
        4: "SG_VisitorArrivals_China",
        5: "SG_VisitorArrivals_Total",
        6: "USDSGD_Avg",
        7: "SG_GDP_YoY",
        8: "SG_SORA_3M",
        9: "SG_NEER_Index",
        10: "SG_SGS_2Y",
        11: "SG_SGS_10Y",
        12: "SG_M2_YoY",
        13: "SG_CoreCPI_YoY",
    }

    col_map_sg2 = {
        0: "SG_GDP_GovtConsump",
        1: "SG_GDP_PrivConsump",
        2: "SG_GDP_GFCF",
        3: "CN_IPI_YoY",
    }

    sg_renamed = sg_data.rename(columns={k+1: v for k, v in col_map_sg.items()})
    sg_renamed = sg_renamed[[v for v in col_map_sg.values() if v in sg_renamed.columns]]

    if not sg2_data.empty:
        sg2_renamed = sg2_data.rename(columns={k+1: v for k, v in col_map_sg2.items()})
        sg2_renamed = sg2_renamed[[v for v in col_map_sg2.values() if v in sg2_renamed.columns]]
        merged = pd.merge(sg_renamed, sg2_renamed, left_index=True, right_index=True, how="outer")
    else:
        merged = sg_renamed

    # Resample to month-end
    merged = merged.resample("ME").last()

    # Derived: yield curve spread
    if "SG_SGS_10Y" in merged.columns and "SG_SGS_2Y" in merged.columns:
        merged["SG_YieldSpread_10Y2Y"] = merged["SG_SGS_10Y"] - merged["SG_SGS_2Y"]

    # Derived: CPI surprise (vs 3M rolling average)
    if "SG_CPI_YoY" in merged.columns:
        merged["SG_CPI_Surprise"] = merged["SG_CPI_YoY"] - merged["SG_CPI_YoY"].rolling(3).mean().shift(1)

    merged.index.name = "Date"
    return merged.reset_index()


def build_global_macro(data_dir: Path) -> pd.DataFrame:
    """Build global macro panel from a licensed macro data vendor bfeus_factor.xlsx."""
    data, names = parse_ceic_file(data_dir / "bfeus_factor__1_.xlsx")
    if data.empty:
        # Try alternate filename
        data, names = parse_ceic_file(data_dir / "bfeus_factor.xlsx")

    col_map = {
        0: "CN_PPI_YoY",
        1: "CN_PMI_Mfg",
        2: "JP_Tankan_Mfg_DI",
        3: "SG_CoreCPI_YoY2",    # duplicate — use as check
        4: "SG_CPI_YoY2",
        5: "SG_GDP_YoY2",
        6: "US_M2_YoY",
        7: "US_Unemployment",
        8: "US_ISM_PMI",
        9: "US_CoreCPI_YoY",
        10: "US_CPI_YoY",
    }

    renamed = data.rename(columns={k+1: v for k, v in col_map.items()})
    keep_cols = ["CN_PPI_YoY", "CN_PMI_Mfg", "JP_Tankan_Mfg_DI",
                 "US_M2_YoY", "US_Unemployment", "US_ISM_PMI",
                 "US_CoreCPI_YoY", "US_CPI_YoY"]
    renamed = renamed[[c for c in keep_cols if c in renamed.columns]]
    renamed = renamed.resample("ME").last()

    # Derived: US PMI surprise
    if "US_ISM_PMI" in renamed.columns:
        renamed["US_ISM_Surprise"] = renamed["US_ISM_PMI"] - renamed["US_ISM_PMI"].rolling(3).mean().shift(1)

    renamed.index.name = "Date"
    return renamed.reset_index()


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: Load CapIQ snapshot (from CSV export)
# ─────────────────────────────────────────────────────────────────────────────

def load_capiq_snapshot(csv_dir: Path) -> pd.DataFrame:
    """Load CIQ_Snapshot.csv — current/LTM valuation data."""
    path = csv_dir / "CIQ_Snapshot.csv"
    if not path.exists():
        print("  CIQ_Snapshot.csv not found — skipping CapIQ data")
        return pd.DataFrame()

    df = pd.read_csv(path)

    # Rename columns to clean names
    col_rename = {
        "Ticker": "Ticker",
        "CapIQ_ID": "CapIQ_ID",
        "Short_Name": "Short_Name",
        "GICS_Sector": "GICS_Sector",
        "MktCap_SGDmn": "CIQ_MktCap",
        "EV_SGDmn": "CIQ_EV",
        "PE_LTM": "CIQ_PE",
        "PB_LTM": "CIQ_PB",
        "EV_EBITDA_LTM": "CIQ_EV_EBITDA",
        "EV_Revenue_LTM": "CIQ_EV_Revenue",
        "DivYield_Fwd_%": "CIQ_DivYield",
        "FCF_Yield_%": "CIQ_FCF_Yield",
        "ROE_%": "CIQ_ROE",
        "ROA_%": "CIQ_ROA",
        "ROIC_%": "CIQ_ROIC",
        "GrossMargin_%": "CIQ_GrossMargin",
        "EBITDA_Margin_%": "CIQ_EBITDA_Margin",
        "NetMargin_%": "CIQ_NetMargin",
        "NetDebt_EBITDA": "CIQ_NetDebt_EBITDA",
        "TotalDebt_Capital_%": "CIQ_Debt_Capital",
        "Revenue_Growth_1Y_%": "CIQ_RevGrowth_1Y",
        "EPS_Growth_1Y_%": "CIQ_EPSGrowth_1Y",
        "Beta_3Y": "CIQ_Beta",
    }

    df = df.rename(columns={k: v for k, v in col_rename.items() if k in df.columns})

    # Convert numeric columns
    numeric_cols = [c for c in df.columns if c.startswith("CIQ_") and c not in ["CIQ_ID"]]
    for c in numeric_cols:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    return df


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: Combine everything into monthly panel
# ─────────────────────────────────────────────────────────────────────────────

def build_full_panel(data_dir: Path, out_dir: Path):
    print("=" * 60)
    print("SGX Multi-Factor FYP — Building Data Panel")
    print("=" * 60)

    # 1. Bloomberg price panel (stock-level, monthly)
    print("\n[1] Loading Bloomberg price data...")
    price_panel = load_bloomberg_price_panel(data_dir)
    if not price_panel.empty:
        print(f"    {price_panel['Ticker'].nunique()} tickers, "
              f"{price_panel['Date'].min().date()} to {price_panel['Date'].max().date()}")
    else:
        print("    No Bloomberg price data found — create PriceData.csv from xlsm")

    # 2. Benchmark
    print("\n[2] Loading benchmark...")
    benchmark = load_bloomberg_benchmark(data_dir)
    if not benchmark.empty:
        print(f"    {len(benchmark)} monthly rows, {benchmark['Date'].min().date()} to {benchmark['Date'].max().date()}")

    # 3. Risk-free rate
    print("\n[3] Loading risk-free rate...")
    rf = load_risk_free(data_dir)
    if not rf.empty:
        print(f"    Ticker: MASB3M | {len(rf)} rows | last={rf['RiskFree_3M'].dropna().iloc[-1]:.3f}%")

    # 4. Bloomberg global market factors
    print("\n[4] Building market factors (SPX, VIX, DXY, FDTR, SPY)...")
    mkt_factors = build_market_factors(data_dir)
    if not mkt_factors.empty:
        print(f"    {len(mkt_factors)} monthly rows")

    # 5. SG macro
    print("\n[5] Building SG macro panel (a licensed macro data vendor)...")
    sg_macro = build_sg_macro(data_dir)
    if not sg_macro.empty:
        print(f"    {len(sg_macro)} rows | cols: {len(sg_macro.columns)-1} series")

    # 6. Global macro
    print("\n[6] Building global macro panel (a licensed macro data vendor)...")
    gl_macro = build_global_macro(data_dir)
    if not gl_macro.empty:
        print(f"    {len(gl_macro)} rows | cols: {len(gl_macro.columns)-1} series")

    # 7. CapIQ snapshot
    print("\n[7] Loading CapIQ snapshot...")
    ciq = load_capiq_snapshot(data_dir)
    if not ciq.empty:
        print(f"    {len(ciq)} tickers loaded")

    # ── Build macro table (one row per month) ──────────────────────────────
    print("\n[8] Merging macro factors...")
    macro_frames = []
    for df in [benchmark, rf, mkt_factors, sg_macro, gl_macro]:
        if df is not None and not df.empty and "Date" in df.columns:
            df["Date"] = pd.to_datetime(df["Date"])
            df["Date"] = df["Date"].dt.to_period("M").dt.to_timestamp("ME")
            macro_frames.append(df.set_index("Date"))

    if macro_frames:
        macro = macro_frames[0]
        for f in macro_frames[1:]:
            macro = macro.merge(f, left_index=True, right_index=True, how="outer", suffixes=("", "_dup"))
            # Drop duplicate columns
            macro = macro[[c for c in macro.columns if not c.endswith("_dup")]]
        macro = macro.reset_index().rename(columns={"index": "Date"})
        macro.to_csv(out_dir / "macro_monthly.csv", index=False)
        print(f"    macro_monthly.csv: {len(macro)} rows × {len(macro.columns)} cols")

    # ── Build stock panel (one row per ticker × month) ─────────────────────
    if not price_panel.empty:
        print("\n[9] Building stock panel...")
        price_panel["Date"] = pd.to_datetime(price_panel["Date"])
        price_panel["Date"] = price_panel["Date"].dt.to_period("M").dt.to_timestamp("ME")

        # Merge CapIQ snapshot (current/LTM — broadcast to all months as approximation)
        # Note: for a proper backtesting study, you'd want CIQSERIES for historical values
        if not ciq.empty:
            ciq_cols = [c for c in ciq.columns if c.startswith("CIQ_") or c == "Ticker"]
            panel = pd.merge(price_panel, ciq[ciq_cols], on="Ticker", how="left")
        else:
            panel = price_panel.copy()

        # Merge macro
        if macro_frames:
            macro_monthly = pd.read_csv(out_dir / "macro_monthly.csv", parse_dates=["Date"])
            panel = pd.merge(panel, macro_monthly, on="Date", how="left")

        # ── Compute derived factors ────────────────────────────────────────

        # Momentum: 12-1 and 6-1 month price momentum
        panel = panel.sort_values(["Ticker", "Date"])

        if "PX_LAST" in panel.columns:
            panel["Return_1M"]  = panel.groupby("Ticker")["PX_LAST"].pct_change(1)
            panel["Return_3M"]  = panel.groupby("Ticker")["PX_LAST"].pct_change(3)
            panel["Return_6M"]  = panel.groupby("Ticker")["PX_LAST"].pct_change(6)
            panel["MOM_12_1"]   = panel.groupby("Ticker")["PX_LAST"].pct_change(12).shift(1)
            panel["MOM_6_1"]    = panel.groupby("Ticker")["PX_LAST"].pct_change(6).shift(1)
            panel["MOM_3_1"]    = panel.groupby("Ticker")["PX_LAST"].pct_change(3).shift(1)

        if "TOT_RETURN" in panel.columns:
            panel["TotRet_1M"] = panel.groupby("Ticker")["TOT_RETURN"].pct_change(1)

        # Size factor: log market cap
        if "MKT_CAP_SGDmn" in panel.columns:
            panel["LogMktCap"] = np.log(panel["MKT_CAP_SGDmn"].clip(lower=1))

        # Value factor: use P/B from Bloomberg (or EV/EBITDA from CapIQ)
        if "PX_TO_BOOK" in panel.columns:
            panel["BM_Ratio"] = 1 / panel["PX_TO_BOOK"].clip(lower=0.01)  # B/M = 1/PB

        # Liquidity: log volume
        if "PX_VOLUME" in panel.columns:
            panel["LogVolume"] = np.log(panel["PX_VOLUME"].clip(lower=1))
            # Amihud illiquidity: |Return| / Volume
            if "Return_1M" in panel.columns:
                panel["Amihud_Illiq"] = panel["Return_1M"].abs() / panel["PX_VOLUME"].clip(lower=1)

        # Cross-sectional z-score normalisation per month
        def cs_zscore(x):
            mu = x.mean(); sig = x.std()
            return (x - mu) / sig if sig > 0 else x * 0

        factor_cols = ["MOM_12_1", "MOM_6_1", "MOM_3_1", "BM_Ratio", "LogMktCap",
                       "CIQ_ROE", "CIQ_EV_EBITDA", "CIQ_DivYield", "CIQ_FCF_Yield",
                       "CIQ_GrossMargin", "CIQ_EBITDA_Margin", "DIV_YIELD", "LogVolume"]

        for col in factor_cols:
            if col in panel.columns:
                z_col = "Z_" + col
                panel[z_col] = panel.groupby("Date")[col].transform(cs_zscore)

        panel.to_csv(out_dir / "panel_monthly.csv", index=False)
        print(f"    panel_monthly.csv: {len(panel)} rows × {len(panel.columns)} cols")
        print(f"    Tickers: {panel['Ticker'].nunique()}")
        print(f"    Date range: {panel['Date'].min().date()} to {panel['Date'].max().date()}")

    print("\nDone. Check panel_monthly.csv and macro_monthly.csv.")
    print("Next: run factor_model.py for cross-sectional ranking and backtesting.")


if __name__ == "__main__":
    build_full_panel(DATA_DIR, OUT_DIR)
