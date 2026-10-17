-- Monthly Spearman rank IC of each score against next month's return, on the names eligible
-- at formation, at least 15 per date, formation months from $start (the canonical Table 1
-- rules). Ties get average ranks, as in scipy.stats.spearmanr, so the IC is the Pearson
-- correlation of those ranks.
WITH x AS (
    SELECT s.m, s.factor, s.score, f.fwd
    FROM scores s
    JOIN eligible e USING (secid, m)
    JOIN fwd f USING (secid, m)
    WHERE f.fwd IS NOT NULL AND s.score IS NOT NULL AND s.m >= $start
), r AS (
    SELECT m, factor,
           rank() OVER (PARTITION BY m, factor ORDER BY score)
             + (count(*) OVER (PARTITION BY m, factor, score) - 1) / 2.0 AS r_score,
           rank() OVER (PARTITION BY m, factor ORDER BY fwd)
             + (count(*) OVER (PARTITION BY m, factor, fwd) - 1) / 2.0   AS r_fwd
    FROM x
)
SELECT factor, m, corr(r_score, r_fwd) AS ic, count(*) AS n
FROM r
GROUP BY factor, m
HAVING count(*) >= 15
ORDER BY factor, m;
