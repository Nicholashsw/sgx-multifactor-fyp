-- Corwin-Schultz spreads, both recipes in code/cs_spreads.py, row for row.

-- Corwin and Schultz (2012): beta from the two single-day ranges, gamma from the two-day
-- range, then alpha and the spread. Negative estimates are set to zero.
CREATE OR REPLACE MACRO cs_alpha(beta, gamma) AS
    (sqrt(2 * beta) - sqrt(beta)) / (3 - 2 * sqrt(2)) - sqrt(gamma / (3 - 2 * sqrt(2)));

CREATE OR REPLACE MACRO cs_from_alpha(a) AS 2 * (exp(a) - 1) / (1 + exp(a));

CREATE OR REPLACE MACRO cs_spread(h, l, h1, l1) AS greatest(cs_from_alpha(cs_alpha(
    pow(ln(h / l), 2) + pow(ln(h1 / l1), 2),
    pow(ln(greatest(h, h1) / least(l, l1)), 2))), 0);


-- Naive recipe: every day with a valid high and low, paired with the next such day.
-- This is what the published cost waterfall used.
CREATE OR REPLACE TABLE cs_naive AS
WITH v AS (
    SELECT secid, d, hi, lo, prc, vol,
           lead(hi) OVER w AS hi1, lead(lo) OVER w AS lo1
    FROM secd
    WHERE hi > 0 AND lo > 0 AND hi >= lo
    WINDOW w AS (PARTITION BY secid ORDER BY d)
)
SELECT secid,
       last_day(d)                                          AS m,
       avg(cs_spread(hi, lo, hi1, lo1)) / 2 * 1e4           AS cs_half_bp,
       avg(vol) * arg_max(prc, d) FILTER (WHERE prc IS NOT NULL) AS adv_sgd
FROM v
WHERE hi1 IS NOT NULL AND lo1 IS NOT NULL
GROUP BY ALL;


-- Traded-days recipe: drop zero-volume and zero-range days, pair each day with the previous
-- kept day only if it is at most five calendar days back, cap at 50%, and need five kept
-- days in the month. Volume and price for ADV come from all valid days.
CREATE OR REPLACE TABLE cs_traded AS
WITH v AS (
    SELECT secid, d, hi, lo, prc, vol, last_day(d) AS m
    FROM secd
    WHERE hi > 0 AND lo > 0 AND hi >= lo
), adv AS (
    SELECT secid, m, avg(vol) * arg_max(prc, d) FILTER (WHERE prc IS NOT NULL) AS adv_sgd
    FROM v GROUP BY ALL
), t AS (
    SELECT secid, d, m,
           CASE WHEN date_diff('day', lag(d) OVER w, d) <= 5
                THEN cs_spread(hi, lo, lag(hi) OVER w, lag(lo) OVER w) END AS s
    FROM v
    WHERE hi > lo * (1 + 1e-12) AND coalesce(vol, 0) > 0
    WINDOW w AS (PARTITION BY secid ORDER BY d)
), mth AS (
    SELECT secid, m, avg(s) FILTER (WHERE s <= 0.5) AS cs, count(*) AS n_days
    FROM t GROUP BY ALL
)
SELECT mth.secid, mth.m, mth.cs / 2 * 1e4 AS cs_half_bp, adv.adv_sgd
FROM mth JOIN adv USING (secid, m)
WHERE mth.n_days >= 5;
