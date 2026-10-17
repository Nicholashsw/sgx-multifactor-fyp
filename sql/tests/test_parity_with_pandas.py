"""The SQL layer against the project's pandas code on the same inputs.

Where the pandas function is importable (cs_spreads.py, factor_model.py) it is called
directly; canonical_rerun.py and waterfall.py run at import, so their selection rules are
restated here line for line, with the source named.
"""

import numpy as np
import pandas as pd
import pytest
from scipy import stats

import report
from conftest import load_code_module


def test_spreads_match_cs_spreads(con, raw_secd):
    cs = load_code_module("cs_spreads")
    x = raw_secd[(raw_secd["curcdd"] == "SGD") & (raw_secd["tpci"].astype(str) == "0")
                 & (raw_secd["exchg"].isin([251, 252]))].copy()
    x = x[x["datadate"] != "2007-12-31"].drop_duplicates(["gvkey", "iid", "datadate"])
    x["datadate"] = pd.to_datetime(x["datadate"])
    x["SecID"] = x["gvkey"].astype(str) + "_" + x["iid"].astype(str)
    for recipe, table in [(cs.naive, "cs_naive"), (cs.traded, "cs_traded")]:
        want = recipe(x).rename(columns={"Date": "m"})
        got = con.execute(f"SELECT secid AS SecID, m, cs_half_bp, adv_sgd FROM {table}").df()
        got["m"] = pd.to_datetime(got["m"])
        j = want.merge(got, on=["SecID", "m"], how="outer", suffixes=("_pd", "_sql"), indicator=True)
        assert (j["_merge"] == "both").all(), f"{table}: key mismatch"
        for c in ["cs_half_bp", "adv_sgd"]:
            np.testing.assert_allclose(j[f"{c}_sql"], j[f"{c}_pd"], rtol=1e-9, atol=1e-9)


def test_zscores_match_factor_model(con):
    fm = load_code_module("factor_model")
    sl = con.execute("SELECT secid, m, factor, x FROM signals_long WHERE factor IN ('bm', 'amihud')").df()
    z = con.execute("SELECT secid, m, factor, z FROM zscores WHERE factor IN ('bm', 'amihud')").df()
    sl["w"] = sl.groupby(["factor", "m"])["x"].transform(fm.winsorise)
    sl["zp"] = sl.groupby(["factor", "m"])["w"].transform(fm.cs_zscore)
    sl.loc[sl["factor"] == "amihud", "zp"] *= -1
    j = sl.merge(z, on=["secid", "m", "factor"])
    assert len(j) == len(sl) == len(z)
    np.testing.assert_allclose(j["z"], j["zp"], atol=1e-10)


def wscore(df, w, cols, min_n=4):
    """canonical_rerun.py, section 4."""
    Z = df[cols]
    W = pd.Series(w).reindex(cols).fillna(0.0)
    s = (Z.fillna(0) * W).sum(axis=1) / Z.notna().mul(W).sum(axis=1).replace(0, np.nan)
    return s.where(Z.notna().sum(axis=1) >= min_n)


def test_composite_matches_canonical_wscore(con):
    p = con.execute("SELECT * FROM panel_legacy").df()
    spec = con.execute("SELECT legacy, weight FROM factor_spec").fetchall()
    want = wscore(p, dict(spec), [k for k, _ in spec])
    np.testing.assert_allclose(p["Composite"], want, atol=1e-12, equal_nan=True)


def _pandas_frame(con):
    p = con.execute("SELECT * FROM panel_legacy").df()
    p["Date"] = pd.to_datetime(p["Date"])
    f = con.execute("SELECT secid AS SecID, m AS Date, fwd AS Fwd FROM fwd").df()
    f["Date"] = pd.to_datetime(f["Date"])
    el = con.execute("SELECT m, secid FROM eligible").df()
    members = {pd.Timestamp(m): set(g["secid"]) for m, g in el.groupby("m")}
    return p.merge(f, on=["SecID", "Date"], how="left"), members


def test_ic_matches_scipy(con):
    q, members = _pandas_frame(con)
    rows = []
    for c in ["Z_MOM_12_1", "Z_EY", "Composite"]:
        for d, g in q.groupby("Date"):
            if d not in members:
                continue
            sub = g[g["SecID"].isin(members[d])][[c, "Fwd"]].dropna()
            if len(sub) >= 15:
                rows.append({"legacy": c, "m": d, "ic_pd": stats.spearmanr(sub[c], sub["Fwd"])[0]})
    want = pd.DataFrame(rows)
    names = {v: k for k, v in report.legacy_names(con).items()}
    want["factor"] = want["legacy"].map(names)
    got = report.monthly_ic(con, "2000-01-01")
    got = got[got["factor"].isin(set(want["factor"]))]
    got["m"] = pd.to_datetime(got["m"])
    j = want.merge(got, on=["factor", "m"], how="outer", indicator=True)
    assert (j["_merge"] == "both").all()
    np.testing.assert_allclose(j["ic"], j["ic_pd"], atol=1e-12)


def test_decile_book_matches_canonical_bt(con):
    """canonical_rerun.py bt(pit=True) and bt(pit=False), composite score."""
    q, members = _pandas_frame(con)
    dts = sorted(q["Date"].unique())
    surv = set(q[q["Date"] == dts[-1]]["SecID"])
    for pit, universe in [(True, "pit"), (False, "survivor")]:
        rows = []
        for i, d in enumerate(dts[:-1]):
            c = q[q["Date"] == d].dropna(subset=["Composite"])
            if pit:
                if d not in members:
                    continue
                c = c[c["SecID"].isin(members[d])]
            else:
                c = c[c["SecID"].isin(surv)]
            k = max(5, len(c) // 10)
            if len(c) < 20:
                continue
            c = c.sort_values(["Composite", "SecID"], ascending=[False, True])
            nr = q[q["Date"] == dts[i + 1]].set_index("SecID")["Return_1M"]
            L, S = nr.reindex(c.head(k)["SecID"]).mean(), nr.reindex(c.tail(k)["SecID"]).mean()
            rows.append({"hold_m": dts[i + 1], "Long": L - 0.001, "LS": L - S - 0.002})
        want = pd.DataFrame(rows).set_index("hold_m")
        got = report.decile_book(con, "composite", universe, "2000-01-01")
        assert list(got.index) == list(want.index)
        np.testing.assert_allclose(got["Long"], want["Long"], atol=1e-12)
        np.testing.assert_allclose(got["LS"], want["LS"], atol=1e-12)


def test_report_tables_run(con):
    t1 = report.table1(con, "2000-01-01", min_months=10)
    t2 = report.table2(con, "2000-01-01")
    assert {"Composite", "Z_MOM_12_1"} <= set(t1["Factor"])
    assert list(t2["Universe"]) == ["Survivor-only", "Survivor-only", "Point-in-time", "Point-in-time"]
    assert t2["Alpha_t"].notna().all()
