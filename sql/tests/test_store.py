"""Point-in-time and data-handling rules of the SQL build."""

import datetime as dt

import pandas as pd
import pytest

import build


def one(con, sql, params=None):
    return con.execute(sql, params or []).fetchone()


def d(s):
    return dt.date.fromisoformat(s)


def test_filters_drop_non_sgd_and_non_common_rows(con):
    assert one(con, "SELECT count(*) FROM secd WHERE d = '2007-12-31'")[0] == 0


def test_duplicate_days_collapse(con):
    assert one(con, "SELECT count(*) FROM (SELECT secid, d FROM secd GROUP BY ALL HAVING count(*) > 1)")[0] == 0


def test_split_does_not_create_a_return(con, raw_secd):
    """1001 halves its price on 2010-03-01; the adjusted monthly return must not."""
    r = one(con, "SELECT ret FROM monthly WHERE secid = '1001_01W' AND m = '2010-03-31'")[0]
    x = raw_secd[raw_secd["gvkey"] == 1001].copy()
    x["m"] = pd.to_datetime(x["datadate"]) + pd.offsets.MonthEnd(0)
    last = x.groupby("m").tail(1).set_index("m")
    adj = last["prccd"] / last["ajexdi"]
    expected = adj[pd.Timestamp("2010-03-31")] / adj[pd.Timestamp("2010-02-28")] - 1
    assert r == pytest.approx(expected, rel=1e-9)
    assert abs(r) < 0.3


def test_dividend_yield_uses_trailing_twelve_months(con, raw_secd):
    got = one(con, "SELECT dy FROM monthly WHERE secid = '1002_01W' AND m = '2010-06-30'")[0]
    x = raw_secd[raw_secd["gvkey"] == 1002].copy()
    x["date"] = pd.to_datetime(x["datadate"])
    window = x[(x["date"] > "2009-06-30") & (x["date"] <= "2010-06-30")]
    price = x[x["date"] <= "2010-06-30"].iloc[-1]["prccd"]
    assert got == pytest.approx(window["div"].sum() / price, rel=1e-9)


def test_fundamentals_wait_for_the_embargo(con):
    """1007's TTM to 2009-12-31 is usable from 2010-04-30, not a month earlier."""
    before = one(con, "SELECT period_end, src FROM fund_pit WHERE secid = '1007_01W' AND m = '2010-03-31'")
    after = one(con, "SELECT period_end, src, ib_sgd, ceq_sgd FROM fund_pit WHERE secid = '1007_01W' AND m = '2010-04-30'")
    assert before == (d("2008-12-31"), "A")
    assert after == (d("2009-12-31"), "Q", 20.0, 400.0)


def test_quarterly_ttm_needs_four_consecutive_quarters(con):
    rows = con.execute("SELECT period_end FROM statements WHERE gvkey = 1007 AND src = 'Q' ORDER BY 1").fetchall()
    assert [r[0] for r in rows] == [d("2009-12-31"), d("2010-03-31")]


def test_foreign_currency_converted_at_formation(con, exports):
    fa = pd.read_csv(exports["funda"])
    ib = fa[(fa["gvkey"] == 1005) & (fa["datadate"] == "2009-12-31")]["ib"].iloc[0]
    got = one(con, "SELECT curcd, ib_sgd FROM fund_pit WHERE secid = '1005_01W' AND m = '2010-06-30'")
    assert got[0] == "USD"
    assert got[1] == pytest.approx(ib * 1.35)


def test_forward_return_never_skips_a_month(con):
    """1004 has no trades in 2010-05: April's forward return is NULL, not June's."""
    assert one(con, "SELECT fwd FROM fwd WHERE secid = '1004_01W' AND m = '2010-04-30'")[0] is None
    assert one(con, "SELECT ret FROM monthly WHERE secid = '1004_01W' AND m = '2010-06-30'")[0] is None


def test_delisted_name_stays_in_the_panel_but_not_in_survivors(con):
    last = one(con, "SELECT max(m) FROM signals WHERE secid = '1003_01W'")[0]
    assert last == d("2011-06-30")
    assert one(con, "SELECT count(*) FROM survivors WHERE secid = '1003_01W'")[0] == 0
    assert one(con, "SELECT delisted FROM security_master WHERE secid = '1003_01W'")[0]


def test_eligibility_follows_the_june_snapshot(con):
    member = lambda s, m: one(con, "SELECT count(*) FROM eligible WHERE secid = ? AND m = ?", [s, m])[0]
    assert member("1029_01W", "2010-05-31") == 1
    assert member("1029_01W", "2010-06-30") == 0
    assert one(con, "SELECT count(*) FROM eligible WHERE secid = '1030_01W'")[0] == 0
    assert one(con, "SELECT count(*) FROM eligible WHERE m < '2008-06-30'")[0] == 0


def test_momentum_skips_the_formation_month(con):
    m = con.execute("SELECT m, ret FROM monthly WHERE secid = '1010_01W' ORDER BY m").df().set_index("m")["ret"]
    got = one(con, "SELECT mom_12_1, mom_6_1 FROM signals WHERE secid = '1010_01W' AND m = '2010-12-31'")
    idx = list(m.index).index(pd.Timestamp("2010-12-31"))
    assert got[0] == pytest.approx((1 + m.iloc[idx - 11:idx]).prod() - 1, rel=1e-12)
    assert got[1] == pytest.approx((1 + m.iloc[idx - 5:idx]).prod() - 1, rel=1e-12)


def test_borrow_matches_through_the_live_identifier(con):
    c = con.execute("SELECT * FROM borrow_match_compare").df().iloc[0]
    assert c["only_live_id"] > 0 and c["only_last_id"] == 0
    early = one(con, "SELECT matched_on FROM borrow WHERE secid = '1002_01W' AND m = '2010-06-30'")[0]
    assert early == "isin"


def test_audits_pass(con):
    failed = [r for r in build.run_audits(con, verbose=False) if r[1] == "fail" and r[2]]
    assert failed == []


def test_missing_required_column_stops_the_build(exports, tmp_path):
    df = pd.read_csv(exports["secd"], dtype=str).drop(columns="ajexdi")
    df.to_csv(tmp_path / "secd.csv", index=False)
    files = dict(exports, secd=tmp_path / "secd.csv")
    with pytest.raises(SystemExit, match="ajexdi"):
        build.build(files, tmp_path / "x.duckdb", verbose=False)


def test_missing_optional_export_is_fine(exports, tmp_path):
    files = {k: v for k, v in exports.items() if k in ("secd", "funda", "constituents")}
    c = build.build(files, tmp_path / "y.duckdb", verbose=False)
    assert one(c, "SELECT count(*) FROM signals")[0] > 0
    # without the FX table a USD reporter keeps its statement but gets no SGD figures
    assert one(c, "SELECT count(*) FROM fund_pit WHERE curcd = 'USD' AND ib_sgd IS NOT NULL")[0] == 0
    assert one(c, "SELECT count(*) FROM signals WHERE secid = '1005_01W' AND bm IS NOT NULL")[0] == 0
