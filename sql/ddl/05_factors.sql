-- Raw signals, cross-sectional z-scores and the preset composite.

-- Raw signals at month-end t, for securities that traded in month t.
--   mom_12_1, mom_6_1   compounded returns over t-11..t-1 and t-5..t-1, every month present
--   bm, ey, roe         point-in-time book equity and TTM income over market cap / book
--   log_mktcap, amihud  signed below (small size and liquidity score positive)
CREATE OR REPLACE TABLE signals AS
SELECT m.secid, m.m, m.ret, m.mktcap, m.amihud, m.dy,
       CASE WHEN count(m.ret) OVER w11 = 11 THEN product(1 + m.ret) OVER w11 - 1 END AS mom_12_1,
       CASE WHEN count(m.ret) OVER w5  = 5  THEN product(1 + m.ret) OVER w5  - 1 END AS mom_6_1,
       CASE WHEN f.ceq_sgd > 0 AND m.mktcap > 0 THEN f.ceq_sgd / m.mktcap END        AS bm,
       CASE WHEN m.mktcap > 0 THEN f.ib_sgd / m.mktcap END                           AS ey,
       CASE WHEN f.ceq_sgd > 0 THEN f.ib_sgd / f.ceq_sgd END                         AS roe,
       CASE WHEN m.mktcap > 0 THEN ln(m.mktcap) END                                  AS log_mktcap
FROM monthly m
LEFT JOIN fund_pit f USING (secid, m)
WINDOW w11 AS (PARTITION BY m.secid ORDER BY m.m ROWS BETWEEN 11 PRECEDING AND 1 PRECEDING),
       w5  AS (PARTITION BY m.secid ORDER BY m.m ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING)
-- windows run over the full grid first; only then are untraded months dropped
QUALIFY m.prc IS NOT NULL;


-- Factor definitions: name in the legacy panel, raw column, sign, preset composite weight.
-- The weights are the project's fixed preset (REPORT_FINAL.md section 3), not fitted here.
CREATE OR REPLACE TABLE factor_spec (factor VARCHAR, legacy VARCHAR, sign DOUBLE, weight DOUBLE);
INSERT INTO factor_spec VALUES
    ('mom_12_1',   'Z_MOM_12_1',  1, 0.20),
    ('mom_6_1',    'Z_MOM_6_1',   1, 0.05),
    ('bm',         'Z_BM_Ratio',  1, 0.20),
    ('dy',         'Z_DIV_YIELD', 1, 0.10),
    ('ey',         'Z_EY',        1, 0.10),
    ('roe',        'Z_ROE',       1, 0.20),
    ('log_mktcap', 'Z_LogMktCap', -1, 0.05),
    ('amihud',     'Z_Amihud',    -1, 0.10);


CREATE OR REPLACE TABLE signals_long AS
UNPIVOT (SELECT secid, m, mom_12_1, mom_6_1, bm, dy, ey, roe, log_mktcap, amihud FROM signals)
ON mom_12_1, mom_6_1, bm, dy, ey, roe, log_mktcap, amihud
INTO NAME factor VALUE x;

DELETE FROM signals_long WHERE x IS NULL OR NOT isfinite(x);


-- Winsorise at the 1st/99th percentile within each date (linear interpolation, as pandas'
-- quantile), then z-score with the sample standard deviation, as code/factor_model.py does.
-- The cross-section is every security with the signal that month; eligibility is applied
-- later, when ICs and books are formed.
CREATE OR REPLACE TABLE zscores AS
WITH bounds AS (
    SELECT secid, m, factor, x,
           quantile_cont(x, 0.01) OVER p AS lo,
           quantile_cont(x, 0.99) OVER p AS hi
    FROM signals_long
    WINDOW p AS (PARTITION BY factor, m)
), w AS (
    SELECT secid, m, factor, least(greatest(x, lo), hi) AS xw FROM bounds
), z AS (
    SELECT secid, m, factor, xw,
           avg(xw) OVER p         AS mu,
           stddev_samp(xw) OVER p AS sd
    FROM w
    WINDOW p AS (PARTITION BY factor, m)
)
SELECT z.secid, z.m, z.factor,
       s.sign * CASE WHEN z.sd > 1e-9 THEN (z.xw - z.mu) / z.sd ELSE 0 END AS z
FROM z JOIN factor_spec s USING (factor);


-- Preset composite: weights renormalised over the factors present, at least four of eight.
CREATE OR REPLACE TABLE composite AS
SELECT secid, m, sum(z.z * s.weight) / sum(s.weight) AS composite, count(*) AS n_factors
FROM zscores z JOIN factor_spec s USING (factor)
GROUP BY secid, m
HAVING count(*) >= 4;


-- Everything a book or an IC needs, long form: each z-scored factor plus the composite.
CREATE OR REPLACE VIEW scores AS
SELECT secid, m, factor, z AS score FROM zscores
UNION ALL
SELECT secid, m, 'composite', composite FROM composite;
