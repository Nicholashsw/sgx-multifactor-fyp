-- Views in the column layout of the legacy pandas inputs, so the existing scripts can run on
-- the SQL build unchanged (build.py --export writes them to CSV).

-- sg_broad_quarterly.csv layout, read by canonical_rerun.py and waterfall.py.
CREATE OR REPLACE VIEW panel_legacy AS
WITH z AS (
    SELECT secid, m,
           max(z) FILTER (WHERE factor = 'mom_12_1')   AS z_mom_12_1,
           max(z) FILTER (WHERE factor = 'mom_6_1')    AS z_mom_6_1,
           max(z) FILTER (WHERE factor = 'bm')         AS z_bm,
           max(z) FILTER (WHERE factor = 'dy')         AS z_dy,
           max(z) FILTER (WHERE factor = 'ey')         AS z_ey,
           max(z) FILTER (WHERE factor = 'roe')        AS z_roe,
           max(z) FILTER (WHERE factor = 'log_mktcap') AS z_size,
           max(z) FILTER (WHERE factor = 'amihud')     AS z_amihud
    FROM zscores
    GROUP BY secid, m
)
SELECT s.secid        AS "SecID",
       s.m            AS "Date",
       s.ret          AS "Return_1M",
       s.mktcap       AS "MKT_CAP",
       s.amihud       AS "Amihud",
       z.z_mom_12_1   AS "Z_MOM_12_1",
       z.z_mom_6_1    AS "Z_MOM_6_1",
       z.z_bm         AS "Z_BM_Ratio",
       z.z_dy         AS "Z_DIV_YIELD",
       z.z_ey         AS "Z_EY",
       z.z_roe        AS "Z_ROE",
       z.z_size       AS "Z_LogMktCap",
       z.z_amihud     AS "Z_Amihud",
       c.composite    AS "Composite"
FROM signals s
LEFT JOIN z USING (secid, m)
LEFT JOIN composite c USING (secid, m)
ORDER BY s.secid, s.m;

-- cs_spreads_monthly.csv / cs_spreads_traded.csv layout.
CREATE OR REPLACE VIEW cs_naive_legacy AS
SELECT secid AS "SecID", m AS "Date", cs_half_bp, adv_sgd FROM cs_naive ORDER BY secid, m;

CREATE OR REPLACE VIEW cs_traded_legacy AS
SELECT secid AS "SecID", m AS "Date", cs_half_bp, adv_sgd FROM cs_traded ORDER BY secid, m;

-- crosswalk_secid_isin_sedol.csv layout.
CREATE OR REPLACE VIEW crosswalk_legacy AS
SELECT secid AS "SecID", isin, sedol FROM crosswalk_last ORDER BY secid;
