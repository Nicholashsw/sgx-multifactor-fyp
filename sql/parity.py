"""
Compare the SQL build with the legacy pandas panel and the verified Table 1.

    python sql/parity.py --db sgx.duckdb --legacy sg_broad_quarterly.csv --out sql_out/

The legacy panel was assembled in notebooks that are not in this repository, so its exact
construction (winsorisation, which cross-section the z-scores use, TTM rules) is not fully
documented. This script does not assume the two builds should agree. It measures where they
do and where they do not, column by column, and puts the two Table 1s side by side:

  coverage       security-months in both builds, legacy only, SQL only
  per column     Pearson and Spearman correlation on the overlap, median absolute
                 difference, share of rows within 1e-6
  Table 1        legacy (results/verified/canonical_table1.csv) against the SQL build

Writes parity_columns.csv and parity_table1.csv to --out. The outputs are summary
statistics, not vendor rows.
"""

import argparse
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

import report

HERE = Path(__file__).resolve().parent
COLUMNS = ["Return_1M", "MKT_CAP", "Amihud", "Z_MOM_12_1", "Z_MOM_6_1", "Z_BM_Ratio", "Z_DIV_YIELD",
           "Z_EY", "Z_ROE", "Z_LogMktCap", "Z_Amihud", "Composite"]


def normalise_keys(df):
    """SecID as int(gvkey)_iid and Date as month-end, whatever the file carried."""
    parts = df["SecID"].astype(str).str.partition("_")
    df = df.copy()
    df["SecID"] = (pd.to_numeric(parts[0], errors="coerce").astype("Int64").astype(str)
                   + "_" + parts[2].str.strip())
    df["Date"] = pd.to_datetime(df["Date"]) + pd.offsets.MonthEnd(0)
    return df


def compare_columns(sql, legacy):
    keys = ["SecID", "Date"]
    both = sql.merge(legacy, on=keys, suffixes=("_sql", "_legacy"))
    out = [{"column": "(keys)", "rows_sql": len(sql), "rows_legacy": len(legacy), "rows_both": len(both),
            "legacy_only": len(legacy) - len(both), "sql_only": len(sql) - len(both)}]
    for c in COLUMNS:
        if c not in legacy.columns:
            out.append({"column": c, "note": "not in legacy panel"})
            continue
        x = both[[f"{c}_sql", f"{c}_legacy"]].dropna()
        row = {"column": c, "rows_sql": int(sql[c].notna().sum()), "rows_legacy": int(legacy[c].notna().sum()),
               "rows_both": len(x)}
        if len(x) > 2:
            d = (x[f"{c}_sql"] - x[f"{c}_legacy"]).abs()
            row.update({"pearson": round(x.corr().iloc[0, 1], 4),
                        "spearman": round(x.corr(method="spearman").iloc[0, 1], 4),
                        "median_abs_diff": float(np.round(d.median(), 6)),
                        "share_within_1e-6": round(float((d <= 1e-6).mean()), 4)})
        out.append(row)
    return pd.DataFrame(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="sgx.duckdb")
    ap.add_argument("--legacy", required=True, help="the legacy sg_broad_quarterly.csv")
    ap.add_argument("--table1", default=str(HERE.parent / "results" / "verified" / "canonical_table1.csv"))
    ap.add_argument("--start", default=report.START)
    ap.add_argument("--out", default="sql_out")
    args = ap.parse_args()

    con = duckdb.connect(args.db, read_only=True)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    sql = normalise_keys(con.execute("SELECT * FROM panel_legacy").df())
    legacy = normalise_keys(pd.read_csv(args.legacy, low_memory=False))
    legacy = legacy[legacy["Date"] >= args.start]
    sql = sql[sql["Date"] >= args.start]
    cols = compare_columns(sql, legacy)
    cols.to_csv(out / "parity_columns.csv", index=False)
    print("PANEL PARITY\n" + cols.to_string(index=False))

    t1 = report.table1(con, args.start)
    ref = pd.read_csv(args.table1)
    side = ref.merge(t1, on="Factor", how="outer", suffixes=("_legacy", "_sql"))
    both = side["Mean_IC_legacy"].notna() & side["Mean_IC_sql"].notna()
    side["sign_agrees"] = (np.sign(side["Mean_IC_legacy"]) == np.sign(side["Mean_IC_sql"])).where(both)
    side.to_csv(out / "parity_table1.csv", index=False)
    print("\nTABLE 1, LEGACY vs SQL\n" + side.to_string(index=False))


if __name__ == "__main__":
    main()
