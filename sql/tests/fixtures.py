"""
Small export files for the unit tests, written in the column layout of the WRDS extracts.

These rows exist only to exercise the SQL. They are built in memory for each test run, are
never written into the repository, and no research result is computed from them.
"""

from pathlib import Path

import numpy as np
import pandas as pd

SECD_COLS = ["gvkey", "iid", "datadate", "isin", "sedol", "curcdd", "exchg", "tpci",
             "prccd", "prchd", "prcld", "cshtrd", "ajexdi", "trfd", "cshoc", "div"]


def _days(start, end):
    return pd.bdate_range(start, end)


def _security(gvkey, days, rng, p0=1.0, vol=0.02, shares=1e8, isin=None, sedol=None):
    r = rng.normal(0.0004, vol, len(days))
    px = p0 * np.exp(np.cumsum(r))
    rng_hl = np.abs(rng.normal(0, vol / 2, len(days))) + 1e-3
    return pd.DataFrame({
        "gvkey": gvkey, "iid": "01W", "datadate": days.strftime("%Y-%m-%d"),
        "isin": isin or f"SG{gvkey:010d}", "sedol": sedol or f"S{gvkey:06d}",
        "curcdd": "SGD", "exchg": 251, "tpci": "0",
        "prccd": px.round(4), "prchd": (px * (1 + rng_hl)).round(4),
        "prcld": (px * (1 - rng_hl)).round(4),
        "cshtrd": rng.integers(0, 200_000, len(days)).astype(float),
        "ajexdi": 1.0, "trfd": 1.0, "cshoc": shares, "div": np.nan,
    })


def write_exports(root, n=30, seed=11):
    """A 30-name universe, 2008-2012, with the edge cases the tests look for.

    1001  a 2-for-1 split on 2010-03-01: prccd halves, and ajexdi is 2 before the split and 1
          after (Compustat divides history down to the current share basis)
    1002  a dividend each June, and an ISIN change on 2011-01-03
    1003  delists 2011-06-15 (last trade), dlrsn 01
    1004  no trades in 2010-05 (a hole in the monthly grid)
    1005  reports in USD (needs the FX table for ratios)
    others plain random walks; one non-SGD row and one tpci = 'F' row are mixed in to be
    filtered out, and one day of 1006 is duplicated.
    """
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    days = _days("2008-01-01", "2012-12-31")
    frames = []
    for i in range(n):
        g = 1001 + i
        f = _security(g, days, rng, p0=rng.uniform(0.5, 5), shares=rng.uniform(5e7, 2e9))
        if g == 1001:
            after = pd.to_datetime(f["datadate"]) >= "2010-03-01"
            f.loc[after, ["prccd", "prchd", "prcld"]] /= 2
            f.loc[~after, "ajexdi"] = 2.0
        if g == 1002:
            june_first = f.groupby(pd.to_datetime(f["datadate"]).dt.to_period("M")).head(1).index
            june_first = [ix for ix in june_first if f.loc[ix, "datadate"][5:7] == "06"]
            f.loc[june_first, "div"] = 0.05
            f.loc[pd.to_datetime(f["datadate"]) >= "2011-01-03", "isin"] = "SGNEWISIN002"
        if g == 1003:
            f = f[pd.to_datetime(f["datadate"]) <= "2011-06-15"]
        if g == 1004:
            f = f[pd.to_datetime(f["datadate"]).dt.to_period("M") != pd.Period("2010-05")]
        frames.append(f)
    secd = pd.concat(frames, ignore_index=True)
    noise = secd.iloc[[0, 1]].copy()
    noise.loc[noise.index[0], "curcdd"] = "USD"
    noise.loc[noise.index[1], "tpci"] = "F"
    noise["datadate"] = "2007-12-31"
    dup = secd[secd["gvkey"] == 1006].iloc[[100]]
    secd = pd.concat([secd, noise, dup], ignore_index=True)[SECD_COLS]
    secd.to_csv(root / "secd.csv", index=False)

    # Annual fundamentals, December year ends; 1005 in USD.
    fa = []
    for i in range(n):
        g = 1001 + i
        for y in range(2006, 2013):
            fa.append({"gvkey": g, "datadate": f"{y}-12-31", "ib": rng.normal(20, 15),
                       "ceq": rng.uniform(50, 500), "curcd": "USD" if g == 1005 else "SGD"})
    pd.DataFrame(fa).to_csv(root / "funda.csv", index=False)

    # Quarterly fundamentals for 1007 only: four consecutive quarters give a TTM figure.
    fq = [{"gvkey": 1007, "datadate": d, "ibq": 5.0, "ceqq": 400.0, "curcdq": "SGD"}
          for d in ["2009-03-31", "2009-06-30", "2009-09-30", "2009-12-31", "2010-03-31"]]
    pd.DataFrame(fq).to_csv(root / "fundq.csv", index=False)

    pd.DataFrame([{"gvkey": 1003, "conm": "GONE LTD", "dlrsn": "01", "dldte": "2011-06-30",
                   "prirow": "01W"}]).to_csv(root / "company.csv", index=False)

    # June snapshots from 2008: everyone but 1030 in 2008 and 2009; from 2010 1029 drops out.
    rows = []
    for y in range(2008, 2013):
        for i in range(n):
            g = 1001 + i
            if g == 1030 or (g == 1029 and y >= 2010):
                continue
            rows.append({"gvkey": g, "iid": "01W", "JuneDate": f"{y}-06-30"})
    pd.DataFrame(rows).to_csv(root / "constituents.csv", index=False)

    months = pd.date_range("2008-01-31", "2012-12-31", freq="ME")
    pd.DataFrame({"date": months.strftime("%Y-%m-%d"), "fic": "SGP",
                  "mportret": rng.normal(0.005, 0.04, len(months))}).to_csv(root / "market.csv", index=False)
    pd.DataFrame({"date": months.strftime("%Y-%m-%d"), "curcd": "USD",
                  "sgd_per_unit": 1.35}).to_csv(root / "fx.csv", index=False)

    # Markit for 1001 and 1002. 1002's rows carry no SEDOL, so before its ISIN change they
    # can only be matched through the ISIN that was live at the time.
    mk = secd[secd["gvkey"].isin([1001, 1002])][["gvkey", "isin", "sedol", "datadate"]].copy()
    mk.loc[mk["gvkey"] == 1002, "sedol"] = None
    mk = mk.drop(columns="gvkey")
    mk["activeavailablevalue"] = 1e6
    mk["indicativefee"] = 25.0
    mk["dcbs"] = 1
    mk.to_csv(root / "markit.csv", index=False)

    names = ["secd", "funda", "fundq", "company", "constituents", "market", "fx", "markit"]
    return {k: root / f"{k}.csv" for k in names}
