-- Eligibility, survivors and forward returns.

-- Each panel month takes the latest June snapshot on or before it. Months before the first
-- snapshot have no eligible names, as in canonical_rerun.py's members().
CREATE OR REPLACE TABLE month_snap AS
SELECT d.m, s.snap
FROM (SELECT DISTINCT m FROM signals) d
ASOF JOIN (SELECT DISTINCT snap FROM constituents) s ON s.snap <= d.m;

CREATE OR REPLACE TABLE eligible AS
SELECT ms.m, c.secid
FROM month_snap ms
JOIN constituents c USING (snap);


-- The survivor-only universe: securities still trading in the last panel month.
CREATE OR REPLACE TABLE survivors AS
SELECT DISTINCT secid FROM signals WHERE m = (SELECT max(m) FROM signals);


-- Next month's return, joined on the calendar: month m+1's row of the same security, from
-- the unfiltered panel. Membership is never applied to the holding month, so a name that
-- leaves the index or delists during the holding month keeps its return (the double-filter
-- trap of ledger B13). A security with no row at m+1 gets NULL, never a later month.
CREATE OR REPLACE TABLE fwd AS
SELECT s.secid, s.m, n.ret AS fwd
FROM signals s
LEFT JOIN monthly n ON n.secid = s.secid AND n.m = last_day(s.m + INTERVAL 1 MONTH);
