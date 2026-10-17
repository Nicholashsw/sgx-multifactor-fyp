-- Typed copies of the licensed exports.
--
-- build.py stages each CSV as an all-VARCHAR src_* table (lower-cased column names, and an
-- empty table with the expected columns when an optional export is absent), so every type,
-- filter and de-duplication decision is made here and nowhere else.

CREATE OR REPLACE MACRO parse_date(x) AS CAST(coalesce(
    try_strptime(trim(x), '%Y-%m-%d'),
    try_strptime(trim(x), '%Y%m%d'),
    try_strptime(trim(x), '%d/%m/%Y'),
    try_strptime(trim(x), '%Y-%m-%d %H:%M:%S')) AS DATE);

CREATE OR REPLACE MACRO num(x) AS TRY_CAST(nullif(trim(x), '') AS DOUBLE);

-- Same key as the pandas scripts: gvkey as an integer, underscore, issue id.
CREATE OR REPLACE MACRO make_secid(gvkey, iid) AS
    CAST(CAST(num(gvkey) AS BIGINT) AS VARCHAR) || '_' || trim(iid);


-- Compustat Global Security Daily, fic = SGP. SGD common stock on the SGX main board (251)
-- and Catalist (252), the filter in code/cs_spreads.py. Prices are not required to be
-- positive here because the spread recipes work from highs and lows alone.
CREATE OR REPLACE TABLE secd AS
SELECT make_secid(gvkey, iid)                  AS secid,
       CAST(num(gvkey) AS BIGINT)              AS gvkey,
       trim(iid)                               AS iid,
       parse_date(datadate)                    AS d,
       nullif(trim(isin), '')                  AS isin,
       nullif(trim(sedol), '')                 AS sedol,
       num(prccd)                              AS prc,
       num(prchd)                              AS hi,
       num(prcld)                              AS lo,
       num(cshtrd)                             AS vol,
       num(ajexdi)                             AS ajex,
       num(trfd)                               AS trf,
       num(cshoc)                              AS shrout,
       num(div)                                AS div
FROM src_secd
WHERE trim(curcdd) = 'SGD'
  AND trim(tpci) = '0'
  AND CAST(num(exchg) AS INTEGER) IN (251, 252)
  AND parse_date(datadate) IS NOT NULL
QUALIFY row_number() OVER (PARTITION BY make_secid(src_secd.gvkey, src_secd.iid), parse_date(datadate)
                           ORDER BY num(prccd) DESC NULLS LAST, num(cshtrd) DESC NULLS LAST) = 1;


-- Company header: delisting reason and date, and the primary issue tag where exported.
CREATE OR REPLACE TABLE company AS
SELECT CAST(num(gvkey) AS BIGINT)   AS gvkey,
       any_value(nullif(trim(conm), ''))   AS conm,
       any_value(nullif(trim(dlrsn), ''))  AS dlrsn,
       any_value(parse_date(dldte))        AS dldte,
       any_value(nullif(trim(prirow), '')) AS prirow
FROM src_company
WHERE num(gvkey) IS NOT NULL
GROUP BY 1;


-- Fundamentals. Compustat can carry more than one row per firm and period end (restated or
-- alternative presentations); the row with both items present wins, then the larger value,
-- so the choice is deterministic.
CREATE OR REPLACE TABLE funda AS
SELECT CAST(num(gvkey) AS BIGINT) AS gvkey,
       parse_date(datadate)       AS period_end,
       num(ib)                    AS ib,
       num(ceq)                   AS ceq,
       nullif(trim(curcd), '')    AS curcd
FROM src_funda
WHERE num(gvkey) IS NOT NULL AND parse_date(datadate) IS NOT NULL
QUALIFY row_number() OVER (PARTITION BY num(src_funda.gvkey), parse_date(datadate)
                           ORDER BY (num(src_funda.ib) IS NULL)::INT + (num(src_funda.ceq) IS NULL)::INT,
                                    num(src_funda.ib) DESC NULLS LAST, num(src_funda.ceq) DESC NULLS LAST) = 1;

CREATE OR REPLACE TABLE fundq AS
SELECT CAST(num(gvkey) AS BIGINT) AS gvkey,
       parse_date(datadate)       AS period_end,
       num(ibq)                   AS ibq,
       num(ceqq)                  AS ceqq,
       nullif(trim(curcdq), '')   AS curcd
FROM src_fundq
WHERE num(gvkey) IS NOT NULL AND parse_date(datadate) IS NOT NULL
QUALIFY row_number() OVER (PARTITION BY num(src_fundq.gvkey), parse_date(datadate)
                           ORDER BY (num(src_fundq.ibq) IS NULL)::INT + (num(src_fundq.ceqq) IS NULL)::INT,
                                    num(src_fundq.ibq) DESC NULLS LAST, num(src_fundq.ceqq) DESC NULLS LAST) = 1;


-- June index-constituent snapshots (the World_Index_Constituents export).
CREATE OR REPLACE TABLE constituents AS
SELECT DISTINCT make_secid(gvkey, iid) AS secid, parse_date(junedate) AS snap
FROM src_constituents
WHERE parse_date(junedate) IS NOT NULL AND num(gvkey) IS NOT NULL;


-- WRDS world index returns; the Singapore series is the alpha benchmark.
CREATE OR REPLACE TABLE bench AS
SELECT last_day(parse_date(date)) AS m, avg(num(mportret)) AS mkt
FROM src_market
WHERE trim(fic) = 'SGP' AND parse_date(date) IS NOT NULL
GROUP BY 1;


-- Markit Securities Finance, daily.
CREATE OR REPLACE TABLE markit AS
SELECT nullif(trim(isin), '')       AS isin,
       nullif(trim(sedol), '')      AS sedol,
       parse_date(datadate)         AS d,
       num(activeavailablevalue)    AS avail,
       num(indicativefee)           AS fee,
       num(dcbs)                    AS dcbs
FROM src_markit
WHERE parse_date(datadate) IS NOT NULL;


-- Optional month-end FX to SGD, for firms reporting in another currency
-- (columns: date, curcd, sgd_per_unit). Without it those firms get no fundamental ratios.
CREATE OR REPLACE TABLE fx AS
SELECT last_day(parse_date(date)) AS m, trim(curcd) AS curcd, any_value(num(sgd_per_unit)) AS sgd_per_unit
FROM src_fx
WHERE parse_date(date) IS NOT NULL
GROUP BY 1, 2;
