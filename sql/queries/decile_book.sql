-- Monthly decile long-short on one score, the canonical Table 2 construction:
-- k = max(5, n // 10) names per leg from at least 20 candidates, equal weight, held one month.
-- Candidates come from the point-in-time eligible set ($universe = 'pit') or from today's
-- survivors ($universe = 'survivor'). Holding returns always come from the unfiltered panel.
-- The 10 bp (long) and 20 bp (long-short) haircuts are applied in report.py, as in
-- canonical_rerun.py.
WITH c AS (
    SELECT s.m, s.secid, s.score
    FROM scores s
    WHERE s.factor = $score
      AND s.score IS NOT NULL
      AND s.m >= $start
      AND s.m < (SELECT max(m) FROM signals)
      AND CASE $universe
              WHEN 'pit'      THEN EXISTS (SELECT 1 FROM eligible e WHERE e.m = s.m AND e.secid = s.secid)
              WHEN 'survivor' THEN s.secid IN (SELECT secid FROM survivors)
          END
), sized AS (
    SELECT m, count(*) AS n, greatest(5, count(*) // 10) AS k
    FROM c GROUP BY m HAVING count(*) >= 20
), ranked AS (
    SELECT c.m, c.secid, z.n, z.k,
           row_number() OVER (PARTITION BY c.m ORDER BY c.score DESC, c.secid)    AS from_top,
           row_number() OVER (PARTITION BY c.m ORDER BY c.score ASC, c.secid DESC) AS from_bottom
    FROM c JOIN sized z USING (m)
)
SELECT last_day(r.m + INTERVAL 1 MONTH)                 AS hold_m,
       any_value(r.n)                                   AS n,
       avg(f.fwd) FILTER (WHERE r.from_top <= r.k)      AS long_ret,
       avg(f.fwd) FILTER (WHERE r.from_bottom <= r.k)   AS short_ret
FROM ranked r
LEFT JOIN fwd f USING (secid, m)
GROUP BY r.m
ORDER BY hold_m;
