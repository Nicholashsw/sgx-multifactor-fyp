"""
Canonical Tables 1 and 2 recomputed from the SQL store.

    python sql/report.py --db sgx.duckdb --out sql_out/

Table 1: mean monthly Spearman IC of each factor and the composite on the point-in-time
universe, Newey-West t at 6 lags, factors with more than 50 monthly ICs (canonical_rerun.py
section 1). Table 2: the decile book on survivors versus the point-in-time universe, with
the same haircuts, performance measures and NW(6) alpha on the WRDS Singapore market return
(section 2). The selection and return logic runs in SQL (queries/); this file only does the
time-series statistics, using the same statsmodels calls as canonical_rerun.py.
"""

import argparse
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
import statsmodels.api as sm

HERE = Path(__file__).resolve().parent
START = "1991-01-01"


def nw_t(a, lags=6):
    """Newey-West t of the mean, as canonical_rerun.nw_t."""
    return sm.OLS(np.asarray(a), np.ones(len(a))).fit(cov_type="HAC", cov_kwds={"maxlags": lags}).tvalues[0]


def perf(r):
    r = r.dropna()
    c = (1 + r).cumprod()
    return {"ann": ((1 + r).prod() ** (12 / len(r)) - 1) * 100,
            "sharpe": r.mean() / r.std() * np.sqrt(12),
            "mdd": ((c - c.cummax()) / c.cummax()).min() * 100}


def alpha(r, bench):
    df = pd.concat([r, bench], axis=1, keys=["s", "b"], sort=True).dropna()
    m = sm.OLS(df["s"], sm.add_constant(df["b"])).fit(cov_type="HAC", cov_kwds={"maxlags": 6})
    return m.params["const"] * 100, m.tvalues["const"], m.params["b"]


def legacy_names(con):
    names = dict(con.execute("SELECT factor, legacy FROM factor_spec").fetchall())
    names["composite"] = "Composite"
    return names


def monthly_ic(con, start=START):
    sql = (HERE / "queries" / "ic.sql").read_text()
    return con.execute(sql, {"start": start}).df()


def table1(con, start=START, min_months=50):
    ic = monthly_ic(con, start)
    names = legacy_names(con)
    rows = []
    for factor, g in ic.groupby("factor"):
        a = g["ic"].dropna().to_numpy()
        if len(a) > min_months:
            rows.append({"Factor": names[factor], "Mean_IC": round(a.mean(), 4),
                         "t_NW6": round(nw_t(a), 2), "n": len(a)})
    if not rows:
        return pd.DataFrame(columns=["Factor", "Mean_IC", "t_NW6", "n"])
    return pd.DataFrame(rows).sort_values("t_NW6", ascending=False).reset_index(drop=True)


def decile_book(con, score="composite", universe="pit", start=START):
    sql = (HERE / "queries" / "decile_book.sql").read_text()
    b = con.execute(sql, {"score": score, "universe": universe, "start": start}).df()
    b["hold_m"] = pd.to_datetime(b["hold_m"])
    b = b.set_index("hold_m")
    b["Long"] = b["long_ret"] - 0.001
    b["LS"] = b["long_ret"] - b["short_ret"] - 0.002
    return b


def table2(con, start=START):
    bench = con.execute("SELECT m, mkt FROM bench ORDER BY m").df()
    bench = bench.set_index(pd.to_datetime(bench["m"]))["mkt"] if len(bench) else None
    rows = []
    for label, universe in [("Survivor-only", "survivor"), ("Point-in-time", "pit")]:
        b = decile_book(con, "composite", universe, start)
        for leg in ["Long", "LS"]:
            p = perf(b[leg])
            row = {"Universe": label, "Leg": leg, "Ann%": round(p["ann"], 1),
                   "Sharpe": round(p["sharpe"], 2), "MaxDD%": round(p["mdd"], 1), "Months": int(b[leg].notna().sum())}
            if bench is not None:
                a, t, be = alpha(b[leg].dropna(), bench)
                row.update({"Alpha%mo": round(a, 2), "Alpha_t": round(t, 2), "Beta": round(be, 2)})
            rows.append(row)
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="sgx.duckdb")
    ap.add_argument("--out", default="sql_out")
    ap.add_argument("--start", default=START, help="first formation month (canonical: 1991-01-01)")
    args = ap.parse_args()

    con = duckdb.connect(args.db, read_only=True)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    t1 = table1(con, args.start)
    t2 = table2(con, args.start)
    t1.to_csv(out / "table1_sql.csv", index=False)
    t2.to_csv(out / "table2_sql.csv", index=False)
    print("TABLE 1 (SQL build, PIT universe)\n" + t1.to_string(index=False))
    print("\nTABLE 2 (SQL build, survivor vs PIT)\n" + t2.to_string(index=False))
    print(f"\nwrote {out / 'table1_sql.csv'} and {out / 'table2_sql.csv'}")


if __name__ == "__main__":
    main()
