-- Point-in-time fundamentals.
--
-- Each statement becomes usable at the month-end ${embargo} months after its period end
-- (RDQ is not populated for SGP, so the embargo is fixed, as everywhere else in the project).
-- Monthly rows pick up the latest statement already usable at that month-end with an ASOF
-- join, so a figure can never be seen before its availability date.

-- Trailing-twelve-month income from four consecutive quarters, accepted only when the four
-- period ends span exactly nine months; anything else (semi-annual reporters, gaps) falls
-- back to the annual statement. Book equity is the latest balance-sheet value.
CREATE OR REPLACE TABLE statements AS
WITH q AS (
    SELECT gvkey, period_end, curcd, ceqq AS ceq,
           sum(ibq)   OVER w4 AS ib_ttm,
           count(ibq) OVER w4 AS n_q,
           date_diff('month', min(period_end) OVER w4, period_end) AS span_m
    FROM fundq
    WINDOW w4 AS (PARTITION BY gvkey ORDER BY period_end ROWS 3 PRECEDING)
), both_sources AS (
    SELECT gvkey, period_end, curcd, ceq, ib_ttm, 'Q' AS src FROM q WHERE n_q = 4 AND span_m = 9
    UNION ALL
    SELECT gvkey, period_end, curcd, ceq, ib AS ib_ttm, 'A' AS src FROM funda
)
SELECT *, last_day(period_end + INTERVAL ${embargo} MONTH) AS available
FROM both_sources
QUALIFY row_number() OVER (PARTITION BY gvkey, period_end ORDER BY src = 'Q' DESC) = 1;


-- Fundamentals as known at each month-end, converted to SGD. A statement more than
-- ${stale_months} months old at the formation date is treated as missing.
CREATE OR REPLACE TABLE fund_pit AS
WITH j AS (
    SELECT m.secid, m.m, s.period_end, s.available, s.src, s.curcd, s.ib_ttm, s.ceq
    FROM monthly m
    ASOF LEFT JOIN statements s
        ON s.gvkey = m.gvkey AND s.available <= m.m
)
SELECT j.secid, j.m, j.period_end, j.available, j.src, j.curcd,
       CASE WHEN j.curcd = 'SGD' THEN 1.0 ELSE f.sgd_per_unit END AS fx_rate,
       j.ib_ttm * (CASE WHEN j.curcd = 'SGD' THEN 1.0 ELSE f.sgd_per_unit END) AS ib_sgd,
       j.ceq    * (CASE WHEN j.curcd = 'SGD' THEN 1.0 ELSE f.sgd_per_unit END) AS ceq_sgd
FROM j
LEFT JOIN fx f ON f.curcd = j.curcd AND f.m = j.m
WHERE j.period_end IS NOT NULL
  AND date_diff('month', j.period_end, j.m) <= ${stale_months};
