-- Integrity checks on a built store. Each block returns the offending rows; build.py counts
-- them. A "fail" check must return nothing. An "info" check is a diagnostic count.
-- Format: a line "-- check: <name> | <fail|info> | <what it means>" opens each block.

-- check: fundamentals_before_available | fail | a statement used before its embargo date
SELECT * FROM fund_pit WHERE available > m;

-- check: snapshot_from_future | fail | eligibility taken from a June snapshot after the month
SELECT * FROM month_snap WHERE snap > m;

-- check: duplicate_panel_rows | fail | more than one row per security-month
SELECT secid, m, count(*) AS n FROM signals GROUP BY ALL HAVING count(*) > 1;

-- check: zscore_not_standard | fail | a date's z-scores do not have mean 0 and sd 1
SELECT factor, m, avg(z) AS mu, stddev_samp(z) AS sd, count(*) AS n
FROM zscores GROUP BY ALL
HAVING count(*) > 2 AND stddev_samp(z) > 0
   AND (abs(avg(z)) > 1e-9 OR abs(stddev_samp(z) - 1) > 1e-9);

-- check: composite_too_few_factors | fail | a composite built from fewer than four factors
SELECT * FROM composite WHERE n_factors < 4;

-- check: momentum_without_full_window | fail | momentum where a month in t-11..t-1 is missing
WITH w AS (
    SELECT secid, m, count(ret) OVER (PARTITION BY secid ORDER BY m
                                      ROWS BETWEEN 11 PRECEDING AND 1 PRECEDING) AS n
    FROM monthly
)
SELECT s.secid, s.m, w.n FROM signals s JOIN w USING (secid, m)
WHERE s.mom_12_1 IS NOT NULL AND w.n < 11;

-- check: spread_out_of_bounds | fail | a negative half-spread, or a traded one above the 50% cap
SELECT 'naive' AS recipe, * FROM cs_naive WHERE cs_half_bp < 0
UNION ALL
SELECT 'traded', * FROM cs_traded WHERE cs_half_bp < 0 OR cs_half_bp > 2500;

-- check: shift_would_skip_a_month | info | gaps where shift(-1) would borrow a later month
-- Rows whose next traded month is not the next calendar month. The calendar join gives
-- them a NULL forward return; a groupby shift(-1) would have used a later month's return.
WITH t AS (
    SELECT secid, m, lead(m) OVER (PARTITION BY secid ORDER BY m) AS next_traded
    FROM signals
)
SELECT * FROM t WHERE next_traded IS NOT NULL AND next_traded <> last_day(m + INTERVAL 1 MONTH);

-- check: held_through_index_exit | info | names leaving the index that keep their holding return
-- Eligible names that are out of the index the next month but still carry that month's
-- return: the double-filter fix (ledger B13) working as intended.
SELECT e.secid, e.m, f.fwd
FROM eligible e
JOIN fwd f USING (secid, m)
LEFT JOIN eligible nx ON nx.secid = e.secid AND nx.m = last_day(e.m + INTERVAL 1 MONTH)
WHERE nx.secid IS NULL AND f.fwd IS NOT NULL
  AND last_day(e.m + INTERVAL 1 MONTH) <= (SELECT max(m) FROM month_snap);

-- check: extreme_monthly_return | info | monthly returns at or below -100% or above +1000%
SELECT secid, m, ret FROM monthly WHERE ret <= -1 OR ret > 10;

-- check: foreign_currency_without_fx | info | fundamentals lost for lack of an FX rate
SELECT secid, m, curcd FROM fund_pit WHERE fx_rate IS NULL;
