-- Markit lendable supply and fees per security-month, matched two ways.
--
-- code/waterfall.py matches Markit to securities through each security's last ISIN, then
-- last SEDOL. A security whose ISIN changed (a capital reorganisation, a re-domicile) is
-- then unmatched, or matched to the wrong line, for its earlier months. Here the match uses
-- the identifier that was live in the month, and both rules are kept so the difference can
-- be counted (borrow_match_compare).

-- Missing fees: the median fee of the same DCBS bucket, then the overall median, as in
-- code/waterfall.py.
CREATE OR REPLACE TABLE markit_filled AS
WITH med AS (SELECT dcbs, median(fee) AS fee_dcbs FROM markit WHERE fee IS NOT NULL GROUP BY dcbs)
SELECT k.isin, k.sedol, k.d, last_day(k.d) AS m, k.avail,
       coalesce(k.fee, med.fee_dcbs, (SELECT median(fee) FROM markit)) AS fee
FROM markit k LEFT JOIN med USING (dcbs);

-- Last observation of each month, per identifier.
CREATE OR REPLACE TABLE markit_by_isin AS
SELECT isin, m, arg_max(avail, d) AS avail, arg_max(fee, d) AS fee
FROM markit_filled WHERE isin IS NOT NULL GROUP BY ALL;

CREATE OR REPLACE TABLE markit_by_sedol AS
SELECT sedol, m, arg_max(avail, d) AS avail, arg_max(fee, d) AS fee
FROM markit_filled WHERE sedol IS NOT NULL GROUP BY ALL;


-- The identifier pair live in each panel month: the latest run starting on or before it.
CREATE OR REPLACE TABLE ids_by_month AS
SELECT s.secid, s.m, i.isin, i.sedol
FROM signals s
ASOF LEFT JOIN security_ids i ON i.secid = s.secid AND i.valid_from <= s.m;

CREATE OR REPLACE TABLE borrow AS
SELECT x.secid, x.m,
       coalesce(bi.avail, bs.avail)                                       AS avail,
       coalesce(bi.fee, bs.fee)                                           AS fee,
       CASE WHEN bi.isin IS NOT NULL THEN 'isin'
            WHEN bs.sedol IS NOT NULL THEN 'sedol' END                    AS matched_on
FROM ids_by_month x
LEFT JOIN markit_by_isin bi  ON bi.isin = x.isin AND bi.m = x.m
LEFT JOIN markit_by_sedol bs ON bs.sedol = x.sedol AND bs.m = x.m;


-- The same months matched through the last-identifier crosswalk, and the comparison.
CREATE OR REPLACE TABLE borrow_lastid AS
SELECT s.secid, s.m, coalesce(bi.avail, bs.avail) AS avail, coalesce(bi.fee, bs.fee) AS fee
FROM signals s
JOIN crosswalk_last c USING (secid)
LEFT JOIN markit_by_isin bi  ON bi.isin = c.isin AND bi.m = s.m
LEFT JOIN markit_by_sedol bs ON bs.sedol = c.sedol AND bs.m = s.m;

CREATE OR REPLACE VIEW borrow_match_compare AS
SELECT count(*)                                                        AS security_months,
       count(*) FILTER (WHERE p.avail IS NOT NULL)                     AS matched_live_id,
       count(*) FILTER (WHERE l.avail IS NOT NULL)                     AS matched_last_id,
       count(*) FILTER (WHERE p.avail IS NOT NULL AND l.avail IS NULL) AS only_live_id,
       count(*) FILTER (WHERE p.avail IS NULL AND l.avail IS NOT NULL) AS only_last_id,
       count(*) FILTER (WHERE p.avail IS NOT NULL AND l.avail IS NOT NULL
                          AND p.avail IS DISTINCT FROM l.avail)        AS both_but_different
FROM borrow p JOIN borrow_lastid l USING (secid, m);
