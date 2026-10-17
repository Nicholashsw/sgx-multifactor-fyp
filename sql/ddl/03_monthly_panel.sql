-- Daily total-return index, then the month-end panel on a complete calendar grid.

-- Total return index = prccd / ajexdi * trfd. trfd is carried forward within a security when
-- a day is blank (a blank would otherwise break the chain), and a security that never reports
-- it gets 1, which leaves its index price-only.
CREATE OR REPLACE TABLE daily AS
SELECT secid, gvkey, d, prc, vol, ajex, shrout,
       prc / ajex * coalesce(last_value(trf IGNORE NULLS) OVER w, 1.0) AS tri
FROM secd
WHERE prc > 0 AND ajex > 0
WINDOW w AS (PARTITION BY secid ORDER BY d ROWS UNBOUNDED PRECEDING);


-- Last trading day of each security-month.
CREATE OR REPLACE TABLE month_end AS
SELECT secid, gvkey, last_day(d) AS m, d AS last_trade, prc, ajex, tri, shrout
FROM daily
QUALIFY row_number() OVER (PARTITION BY secid, last_day(d) ORDER BY d DESC) = 1;


-- Every calendar month from a security's first to its last month-end, traded or not.
-- Because the grid has no holes, "the previous row" always means "the previous calendar
-- month", so LAG and ROWS windows below are calendar-correct by construction. A month with
-- no trade is a row with a NULL price, and the returns either side of it come out NULL
-- instead of silently spanning two months.
CREATE OR REPLACE TABLE month_grid AS
SELECT secid, gvkey, last_day(CAST(x AS DATE)) AS m
FROM (
    SELECT secid, gvkey,
           unnest(generate_series(CAST(date_trunc('month', min(m)) AS TIMESTAMP),
                                  CAST(date_trunc('month', max(m)) AS TIMESTAMP),
                                  INTERVAL 1 MONTH)) AS x
    FROM month_end
    GROUP BY secid, gvkey
);


-- Amihud inputs per month: sum of |daily return| / SGD volume (x 1e6) over traded days whose
-- return spans at most a week.
CREATE OR REPLACE TABLE illiq_month AS
WITH r AS (
    SELECT secid, d, prc, vol,
           tri / lag(tri) OVER w - 1          AS r,
           date_diff('day', lag(d) OVER w, d) AS gap
    FROM daily
    WINDOW w AS (PARTITION BY secid ORDER BY d)
)
SELECT secid, last_day(d) AS m, sum(abs(r) / (vol * prc)) * 1e6 AS illiq_sum, count(*) AS n_days
FROM r
WHERE vol > 0 AND r IS NOT NULL AND gap <= 7
GROUP BY ALL;


-- Cash dividends per share, put on the current share basis with the ex-date adjustment factor.
CREATE OR REPLACE TABLE div_month AS
SELECT secid, last_day(d) AS m, sum(div / ajex) AS div_adj
FROM secd
WHERE div > 0 AND ajex > 0
GROUP BY ALL;


-- The monthly panel. Primary issues only.
--   ret     month-end to month-end total return; NULL if either month-end is missing
--   mktcap  SGD millions
--   amihud  trailing three months including t (all known at the month-t close), >= 15 days
--   dy      trailing 12-month dividends over the month-end price, on the same share basis;
--           needs 12 listed months and NULL when the export carries no div column
CREATE OR REPLACE TABLE monthly AS
SELECT g.secid,
       g.gvkey,
       g.m,
       e.last_trade,
       e.prc,
       e.tri,
       e.tri / lag(e.tri) OVER w - 1                                         AS ret,
       e.shrout * e.prc / 1e6                                                AS mktcap,
       CASE WHEN sum(i.n_days) OVER w3 >= 15
            THEN sum(i.illiq_sum) OVER w3 / sum(i.n_days) OVER w3 END        AS amihud,
       CASE WHEN (SELECT has_div FROM build_caps) AND count(*) OVER w12 = 12 AND e.prc > 0
            THEN coalesce(sum(v.div_adj) OVER w12, 0) / (e.prc / e.ajex) END AS dy
FROM month_grid g
JOIN security_master sm ON sm.secid = g.secid AND sm.is_primary
LEFT JOIN month_end e   ON e.secid = g.secid AND e.m = g.m
LEFT JOIN illiq_month i ON i.secid = g.secid AND i.m = g.m
LEFT JOIN div_month v   ON v.secid = g.secid AND v.m = g.m
WINDOW w   AS (PARTITION BY g.secid ORDER BY g.m),
       w3  AS (PARTITION BY g.secid ORDER BY g.m ROWS 2 PRECEDING),
       w12 AS (PARTITION BY g.secid ORDER BY g.m ROWS 11 PRECEDING);
