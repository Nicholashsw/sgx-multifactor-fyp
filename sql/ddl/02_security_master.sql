-- Security master and identifier history.

-- One row per security: listing window, exit, and whether it is the firm's primary issue.
-- Without a prirow tag in the company export every issue counts as primary.
CREATE OR REPLACE TABLE security_master AS
SELECT s.secid,
       s.gvkey,
       s.iid,
       c.conm,
       min(s.d)                                     AS first_date,
       max(s.d)                                     AS last_date,
       c.dlrsn,
       c.dldte,
       c.dlrsn IS NOT NULL                          AS delisted,
       c.prirow IS NULL OR c.prirow = s.iid         AS is_primary
FROM secd s
LEFT JOIN company c USING (gvkey)
GROUP BY s.secid, s.gvkey, s.iid, c.conm, c.dlrsn, c.dldte, c.prirow;


-- ISIN and SEDOL as a type-2 history: one row per unbroken run of the same identifier pair.
-- Joining a dated vendor file (Markit) through this table matches the identifier that was
-- live on that date, rather than the last one the security ever carried.
CREATE OR REPLACE TABLE security_ids AS
WITH marked AS (
    SELECT secid, d, isin, sedol,
           CASE WHEN isin IS DISTINCT FROM lag(isin) OVER w
                  OR sedol IS DISTINCT FROM lag(sedol) OVER w THEN 1 ELSE 0 END AS changed
    FROM secd
    WINDOW w AS (PARTITION BY secid ORDER BY d)
), runs AS (
    SELECT *, sum(changed) OVER (PARTITION BY secid ORDER BY d) AS run_id FROM marked
)
SELECT secid, isin, sedol, min(d) AS valid_from, max(d) AS valid_to
FROM runs
GROUP BY secid, run_id, isin, sedol;


-- The crosswalk code/cs_spreads.py writes: each security's last non-blank ISIN and SEDOL.
-- Kept so the two Markit matching rules can be compared (see 09_borrow.sql).
CREATE OR REPLACE TABLE crosswalk_last AS
SELECT secid,
       arg_max(isin, d) FILTER (WHERE isin IS NOT NULL)   AS isin,
       arg_max(sedol, d) FILTER (WHERE sedol IS NOT NULL) AS sedol
FROM secd
GROUP BY secid;
