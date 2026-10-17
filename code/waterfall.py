"""
Cost waterfall on the broad composite (ledger D1), and the same waterfall for the
other weighting schemes in canonical Table 4 (ledger C13).

Needs these licensed files in the working folder (none ship with the repo):
  sg_broad_quarterly.csv, World_Index_Constituents.csv, more/Monthly_World_Indices.csv,
  crosswalk_secid_isin_sedol.csv, cs_spreads_monthly.csv and the Markit export in MARKIT.

Decile long-short on the point-in-time universe, formed monthly from 2003. Stages:
  1. gross
  2. Corwin-Schultz half-spread on both legs, charged every month
  3. shorts limited to names Markit showed as lendable the month before
  4. Markit indicative fee on the shorts
Alpha is the Newey-West (6 lags) intercept on the WRDS Singapore market return.
The long-only rows hold the top decile alone, gross and after its spreads; their alpha
on the market return is the index-hedged version.

Two ways to charge spreads. "Every month" (the published waterfall) charges one
half-spread on every held name each month, which is what a book costs if half of it
turns over monthly. "Traded" charges a half-spread only on the names actually bought
and sold that month, so it follows each scheme's real turnover.

Run: python waterfall.py
     SGX_PANEL=exports/sg_broad_quarterly.csv python waterfall.py --spreads exports/cs_spreads_traded.csv
     python waterfall.py --spreads cs_spreads_traded.csv --out waterfall_schemes_traded_days.csv
The default run uses the spreads the published waterfall used and also writes
waterfall_definitive.csv (preset weights); --spreads swaps in another spread file
built by cs_spreads.py.
"""

import argparse
import os

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy import stats

ap = argparse.ArgumentParser()
ap.add_argument("--spreads", default="cs_spreads_monthly.csv")
ap.add_argument("--out", default="waterfall_schemes.csv")
args = ap.parse_args()

MARKIT = "newz/npfsiwyafic9oihc.csv"
PANEL = os.environ.get("SGX_PANEL", "sg_broad_quarterly.csv")  # sql/build.py --export writes one
FILES = [PANEL, "World_Index_Constituents.csv", "more/Monthly_World_Indices.csv",
         "crosswalk_secid_isin_sedol.csv", args.spreads, MARKIT]
START = pd.Timestamp("2003-01-01")

for f in FILES:
    if not os.path.exists(f):
        raise SystemExit(f"missing: {f}")

q = pd.read_csv(PANEL, parse_dates=["Date"]).sort_values(["SecID", "Date"])
q["Ret"] = q["Return_1M"]
xw = pd.read_csv("crosswalk_secid_isin_sedol.csv")
cs = pd.read_csv(args.spreads, parse_dates=["Date"])

wc = pd.read_csv("World_Index_Constituents.csv", parse_dates=["JuneDate"])
wc["SecID"] = wc["gvkey"].astype(str) + "_" + wc["iid"].astype(str)
snaps = sorted(wc["JuneDate"].unique())


def members(d):
    """Constituents from the latest June snapshot on or before d."""
    v = [s for s in snaps if s <= d]
    return set(wc[wc["JuneDate"] == v[-1]]["SecID"]) if v else None


mw = pd.read_csv("more/Monthly_World_Indices.csv")
mw["date"] = pd.to_datetime(mw["date"]) + pd.offsets.MonthEnd(0)
bench = mw[mw["fic"] == "SGP"].set_index("date")["mportret"]

# Markit: last lendable value and fee per security-month, matched on ISIN, then SEDOL.
mk = pd.read_csv(MARKIT, usecols=["isin", "sedol", "datadate", "activeavailablevalue", "indicativefee", "dcbs"],
                 low_memory=False)
mk["datadate"] = pd.to_datetime(mk["datadate"])
mk["Date"] = mk["datadate"] + pd.offsets.MonthEnd(0)
for c in ["activeavailablevalue", "indicativefee", "dcbs"]:
    mk[c] = pd.to_numeric(mk[c], errors="coerce")
# missing fees: median fee for the same DCBS bucket, then the overall median
mk["fee"] = (mk["indicativefee"].fillna(mk["dcbs"].map(mk.groupby("dcbs")["indicativefee"].median()))
             .fillna(mk["indicativefee"].median()))
mkm = (mk.sort_values("datadate").groupby(["isin", "sedol", "Date"])
       .agg(avail=("activeavailablevalue", "last"), fee=("fee", "last")).reset_index())
by_isin = xw.dropna(subset=["isin"]).merge(mkm, on="isin")[["SecID", "Date", "avail", "fee"]]
rest = xw[~xw["SecID"].isin(set(by_isin["SecID"]))].dropna(subset=["sedol"])
by_sedol = rest.merge(mkm, on="sedol")[["SecID", "Date", "avail", "fee"]]
mm = (pd.concat([by_isin, by_sedol], ignore_index=True).groupby(["SecID", "Date"])
      .agg(avail=("avail", "max"), fee=("fee", "median")).reset_index())
print(f"Markit match: {mm['SecID'].nunique()} of {xw['SecID'].nunique()} securities")

q = q.merge(mm, on=["SecID", "Date"], how="left").merge(cs, on=["SecID", "Date"], how="left")
q = q.sort_values(["SecID", "Date"])
for c in ["avail", "fee", "cs_half_bp", "adv_sgd"]:
    q[c + "_l"] = q.groupby("SecID")[c].shift(1)  # known at formation

# ---- the four scores from canonical Table 4 (same rules as canonical_rerun.py) ----
ZC = ["Z_MOM_12_1", "Z_MOM_6_1", "Z_BM_Ratio", "Z_DIV_YIELD", "Z_EY", "Z_ROE", "Z_LogMktCap", "Z_Amihud"]
PRESET = {"Z_MOM_12_1": .20, "Z_MOM_6_1": .05, "Z_BM_Ratio": .20, "Z_DIV_YIELD": .10,
          "Z_EY": .10, "Z_ROE": .20, "Z_LogMktCap": .05, "Z_Amihud": .10}


def wscore(df, w, cols, min_n=4):
    """Weighted mean of the z-scores present, blank if fewer than min_n are present."""
    z = df[cols]
    wt = pd.Series(w).reindex(cols).fillna(0.0)
    s = (z.fillna(0) * wt).sum(axis=1) / z.notna().mul(wt).sum(axis=1).replace(0, np.nan)
    return s.where(z.notna().sum(axis=1) >= min_n)


recent = q["Date"] >= "1991-01-01"
assert np.allclose(wscore(q[recent], PRESET, ZC), q.loc[recent, "Composite"], atol=1e-9, equal_nan=True)
q["Composite_ExQuality"] = wscore(q, {k: v for k, v in PRESET.items() if k != "Z_ROE"},
                                  [c for c in ZC if c != "Z_ROE"])
q["Composite_Equal"] = wscore(q, {c: 1.0 for c in ZC}, ZC)

# Walk-forward weights: mean of past monthly ICs only (from 1991, next month's return joined on
# the calendar, at least 15 names a date), negatives set to zero, rescaled to sum to 1; equal
# weights until a factor has 36 months of ICs.
nxt = q[["SecID", "Date", "Return_1M"]].rename(columns={"Return_1M": "Fwd"})
nxt["Date"] = nxt["Date"] - pd.offsets.MonthEnd(1)
f = q.loc[recent, ["SecID", "Date"] + ZC].merge(nxt, on=["SecID", "Date"], how="left")
icm = {}
for d, g in f.groupby("Date"):
    am = members(d)
    if am is None:
        continue
    g = g[g["SecID"].isin(am)]
    icm[d] = {}
    for c in ZC:
        sub = g[[c, "Fwd"]].dropna()
        if len(sub) >= 15:
            icm[d][c] = stats.spearmanr(sub[c], sub["Fwd"])[0]
icm = pd.DataFrame.from_dict(icm, orient="index").reindex(columns=ZC).sort_index()
q["Composite_WF"] = np.nan
for d, idx in q.groupby("Date").groups.items():
    h = icm[icm.index < d]
    mu = h.mean().where(h.notna().sum() >= 36).clip(lower=0).fillna(0)
    w = (mu / mu.sum()).to_dict() if mu.sum() > 0 else {c: 1 / len(ZC) for c in ZC}
    q.loc[idx, "Composite_WF"] = wscore(q.loc[idx], w, ZC)

dts = sorted(q["Date"].unique())


def nwa(r, label):
    r = r.dropna()
    df = pd.concat([r, bench], axis=1, keys=["s", "b"], sort=True).dropna()
    m = sm.OLS(df["s"], sm.add_constant(df["b"])).fit(cov_type="HAC", cov_kwds={"maxlags": 6})
    c = (1 + r).cumprod()
    return {"Stage": label, "Ann%": round(((1 + r).prod() ** (12 / len(r)) - 1) * 100, 2),
            "Sharpe": round(r.mean() / r.std() * np.sqrt(12), 2),
            "MaxDD%": round(((c - c.cummax()) / c.cummax()).min() * 100, 1),
            "Alpha%mo": round(m.params["const"] * 100, 3), "t": round(m.tvalues["const"], 2), "N": len(r)}


def traded_cost(new, old, hs, fill):
    """Half-spread on the names bought and sold this month, as a fraction of the leg."""
    def spread(s):
        v = hs.get(s, np.nan)
        return fill if pd.isna(v) else v
    c = sum(spread(s) for s in new - old) / len(new)
    if old:
        c += sum(spread(s) for s in old - new) / len(old)
    return c / 1e4


def bt(score, use_cs=False, screen=False, fee=False, long_only=False, traded=False):
    """Monthly decile book; returns the return series and average one-way turnover."""
    rows, turn, prev, book = [], [], None, None
    for i, d in enumerate(dts[:-1]):
        if d < START:
            continue
        am = members(d)
        if am is None:
            continue
        c = q[(q["Date"] == d) & (q["SecID"].isin(am))].dropna(subset=[score])
        if len(c) < 40:
            continue
        k = max(5, len(c) // 10)
        c = c.sort_values(score, ascending=False)
        lo, sh = c.head(k), c.tail(k)
        held = (set(lo["SecID"]), set(sh["SecID"]))
        if prev is not None:
            legs = (0,) if long_only else (0, 1)
            turn.append(np.mean([len(held[j] - prev[j]) / k for j in legs]))
        prev = held
        if long_only:
            cost = lo["cs_half_bp_l"].fillna(lo["cs_half_bp_l"].median()).mean() / 1e4 if use_cs else 0.0
            if use_cs and traded:
                hs = q[q["Date"] == d].drop_duplicates("SecID").set_index("SecID")["cs_half_bp_l"]
                new = set(lo["SecID"])
                cost = traded_cost(new, book or set(), hs, lo["cs_half_bp_l"].median())
                book = new
            nr = q[q["Date"] == dts[i + 1]].drop_duplicates("SecID").set_index("SecID")["Ret"]
            rl = nr.reindex(lo["SecID"]).mean()
            if not np.isnan(rl):
                rows.append({"Date": dts[i + 1], "R": rl - cost})
            continue
        fee_cost = 0.0
        if screen:
            sh = sh[sh["avail_l"].fillna(0) > 0]
            if len(sh) < 3:
                continue
            if fee:
                fee_cost = float(sh["fee_l"].fillna(0).mean()) / 12
        if use_cs:
            cl = lo["cs_half_bp_l"].fillna(lo["cs_half_bp_l"].median())
            cx = sh["cs_half_bp_l"].fillna(sh["cs_half_bp_l"].median())
            cost = (cl.mean() + cx.mean()) / 1e4
        else:
            cost = 0.0
        if use_cs and traded:
            hs = q[q["Date"] == d].drop_duplicates("SecID").set_index("SecID")["cs_half_bp_l"]
            new = (set(lo["SecID"]), set(sh["SecID"]))
            old = book or (set(), set())
            cost = (traded_cost(new[0], old[0], hs, lo["cs_half_bp_l"].median())
                    + traded_cost(new[1], old[1], hs, sh["cs_half_bp_l"].median()))
            book = new
        nr = q[q["Date"] == dts[i + 1]].drop_duplicates("SecID").set_index("SecID")["Ret"]
        rl, rs = nr.reindex(lo["SecID"]).mean(), nr.reindex(sh["SecID"]).mean()
        if np.isnan(rl) or np.isnan(rs):
            continue
        rows.append({"Date": dts[i + 1], "R": rl - rs - cost - fee_cost})
    return pd.DataFrame(rows).set_index("Date")["R"], np.mean(turn)


STAGES = [("1. Gross signal", {}),
          ("2. + Corwin-Schultz per-name spreads", {"use_cs": True}),
          ("3. + Markit borrow availability screen", {"use_cs": True, "screen": True}),
          ("4. + Markit borrow fee", {"use_cs": True, "screen": True, "fee": True})]
LONG_ONLY = [("Long-only gross", {"long_only": True}),
             ("Long-only + Corwin-Schultz spreads", {"long_only": True, "use_cs": True})]
TRADED = [("2. + spreads on traded names", {"use_cs": True, "traded": True}),
          ("3. + Markit borrow availability screen", {"use_cs": True, "traded": True, "screen": True}),
          ("4. + Markit borrow fee", {"use_cs": True, "traded": True, "screen": True, "fee": True})]
LONG_ONLY_TRADED = [("Long-only + spreads on traded names", {"long_only": True, "use_cs": True, "traded": True})]
RUNS = [("Long-short", "Every month", STAGES), ("Long-short", "Traded", TRADED),
        ("Long-only", "Every month", LONG_ONLY), ("Long-only", "Traded", LONG_ONLY_TRADED)]
out = []
for score in ["Composite", "Composite_ExQuality", "Composite_Equal", "Composite_WF"]:
    for book_name, costing, stages in RUNS:
        for label, kw in stages:
            r, turnover = bt(score, **kw)
            out.append({"Score": score, "Book": book_name, "Costing": costing, **nwa(r, label),
                        "Turnover": round(turnover, 3)})
res = pd.DataFrame(out)
print(res.to_string(index=False))

if args.spreads == "cs_spreads_monthly.csv":
    main = (res["Score"] == "Composite") & (res["Book"] == "Long-short") & (res["Costing"] == "Every month")
    res[main].drop(columns=["Score", "Book", "Costing", "Turnover"]).to_csv("waterfall_definitive.csv", index=False)
    print("\nSaved waterfall_definitive.csv")
res.to_csv(args.out, index=False)
print(f"Saved {args.out}")
