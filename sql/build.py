"""
Build the point-in-time SGX research store (DuckDB) from the licensed exports.

    python sql/build.py --sources sql/sources.toml --db sgx.duckdb
    python sql/build.py --sources sql/sources.toml --db sgx.duckdb --export exports/

The sources file maps each export to a path (see sources.example.toml). Required: the
Compustat Global Security Daily and Fundamentals Annual extracts and the June constituent
snapshots. Optional: Fundamentals Quarterly, the company header, the WRDS world index
returns, Markit, and a month-end FX table. A missing required file or column stops the
build; nothing is filled in or made up.

--export writes the SQL-built panel and spread files in the layouts the pandas scripts read
(sg_broad_quarterly.csv, cs_spreads_monthly.csv, cs_spreads_traded.csv,
crosswalk_secid_isin_sedol.csv), so canonical_rerun.py and waterfall.py can be pointed at
them. They contain vendor-derived rows: never commit them.
"""

import argparse
import re
import sys
import time
import tomllib
from pathlib import Path
from string import Template

import duckdb

HERE = Path(__file__).resolve().parent

# export -> (required columns, optional columns, required export?)
SOURCES = {
    "secd": ({"gvkey", "iid", "datadate", "isin", "sedol", "curcdd", "exchg", "tpci",
              "prccd", "prchd", "prcld", "cshtrd", "ajexdi", "trfd", "cshoc"}, {"div"}, True),
    "funda": ({"gvkey", "datadate", "ib", "ceq", "curcd"}, set(), True),
    "constituents": ({"gvkey", "iid", "junedate"}, set(), True),
    "fundq": ({"gvkey", "datadate", "ibq", "ceqq", "curcdq"}, set(), False),
    "company": ({"gvkey", "dlrsn", "dldte"}, {"conm", "prirow"}, False),
    "market": ({"date", "fic", "mportret"}, set(), False),
    "markit": ({"isin", "sedol", "datadate", "activeavailablevalue", "indicativefee", "dcbs"},
               set(), False),
    "fx": ({"date", "curcd", "sgd_per_unit"}, set(), False),
}

DEFAULTS = {"embargo_months": 4, "stale_months": 18}

EXPORTS = {
    "sg_broad_quarterly.csv": "panel_legacy",
    "cs_spreads_monthly.csv": "cs_naive_legacy",
    "cs_spreads_traded.csv": "cs_traded_legacy",
    "crosswalk_secid_isin_sedol.csv": "crosswalk_legacy",
}


def _quote(path):
    return "'" + str(path).replace("'", "''") + "'"


def _csv_columns(con, path):
    rows = con.execute(f"DESCRIBE SELECT * FROM read_csv({_quote(path)}, header = true, "
                       f"all_varchar = true)").fetchall()
    return [r[0] for r in rows]


def stage(con, name, path):
    """Load one export as an all-VARCHAR src_<name> table with lower-case column names.

    A missing optional export becomes an empty table with the expected columns, and a
    missing optional column becomes an all-NULL column, so the typed layer has one shape.
    Returns the set of optional columns that were actually present.
    """
    required, optional, is_required = SOURCES[name]
    if path is None:
        if is_required:
            raise SystemExit(f"missing required export: {name}")
        cols = ", ".join(f'NULL::VARCHAR AS "{c}"' for c in sorted(required | optional))
        con.execute(f"CREATE OR REPLACE TABLE src_{name} AS SELECT {cols} LIMIT 0")
        return set()

    path = Path(path)
    if not path.exists():
        raise SystemExit(f"{name}: file not found: {path}")
    cols = _csv_columns(con, path)
    lower = {c.lower(): c for c in cols}
    missing = required - lower.keys()
    if missing:
        raise SystemExit(f"{name} ({path}) lacks required columns: {', '.join(sorted(missing))}")
    present = optional & lower.keys()
    select = [f'"{lower[c]}" AS "{c}"' for c in sorted(required | present)]
    select += [f'NULL::VARCHAR AS "{c}"' for c in sorted(optional - present)]
    con.execute(f"CREATE OR REPLACE TABLE src_{name} AS SELECT {', '.join(select)} "
                f"FROM read_csv({_quote(path)}, header = true, all_varchar = true)")
    return present


def load_sources(sources_file):
    cfg = tomllib.loads(Path(sources_file).read_text())
    root = Path(cfg.get("root", Path(sources_file).parent)).expanduser()
    files = {k: (root / v if v else None) for k, v in cfg.get("files", {}).items()}
    unknown = files.keys() - SOURCES.keys()
    if unknown:
        raise SystemExit(f"unknown exports in {sources_file}: {', '.join(sorted(unknown))}")
    params = {**DEFAULTS, **cfg.get("params", {})}
    return files, params


def statements(sql):
    """Split a script on lines that end a statement.

    DuckDB's parser rejects a script in which two statements reuse a WINDOW name, so each
    statement is sent on its own. Statements here end with ';' at the end of a code line.
    """
    out, buf = [], []
    for line in sql.splitlines():
        buf.append(line)
        if not line.lstrip().startswith("--") and line.rstrip().endswith(";"):
            out.append("\n".join(buf))
            buf = []
    if any(l.strip() and not l.lstrip().startswith("--") for l in buf):
        out.append("\n".join(buf))
    return out


def run_sql_file(con, path, params):
    sql = Template(Path(path).read_text()).safe_substitute(
        embargo=int(params["embargo_months"]), stale_months=int(params["stale_months"]))
    for stmt in statements(sql):
        try:
            con.execute(stmt)
        except duckdb.Error as e:
            first = next(l for l in stmt.splitlines() if l.strip() and not l.lstrip().startswith("--"))
            raise SystemExit(f"{Path(path).name}: {first.strip()}\n  {e}") from e


def build(files, db_path, params=None, verbose=True):
    """Stage the exports and run every DDL file in order. Returns the open connection."""
    params = {**DEFAULTS, **(params or {})}
    con = duckdb.connect(str(db_path))
    say = print if verbose else (lambda *a, **k: None)

    present = {}
    for name in SOURCES:
        present[name] = stage(con, name, files.get(name))
        n = con.execute(f"SELECT count(*) FROM src_{name}").fetchone()[0]
        say(f"  staged {name:<13} {n:>12,} rows" + ("" if files.get(name) else "  (not supplied)"))

    con.execute("CREATE OR REPLACE TABLE build_caps AS SELECT ? AS has_div, ? AS embargo_months, "
                "? AS stale_months, now() AS built_at",
                ["div" in present["secd"], int(params["embargo_months"]), int(params["stale_months"])])

    for path in sorted((HERE / "ddl").glob("*.sql")):
        t0 = time.perf_counter()
        run_sql_file(con, path, params)
        say(f"  {path.name:<28} {time.perf_counter() - t0:6.1f}s")
    return con


def run_audits(con, verbose=True):
    """Run audits.sql. Returns a list of (check, severity, rows, description)."""
    text = (HERE / "audits.sql").read_text()
    blocks = re.split(r"^-- check: ", text, flags=re.M)[1:]
    results = []
    for block in blocks:
        header, _, body = block.partition("\n")
        name, severity, desc = [s.strip() for s in header.split("|", 2)]
        sql = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("--")).strip()
        n = con.execute(f"SELECT count(*) FROM ({sql.rstrip(';')})").fetchone()[0]
        results.append((name, severity, n, desc))
    if verbose:
        for name, severity, n, desc in results:
            flag = "FAIL" if severity == "fail" and n else ("ok" if severity == "fail" else "info")
            print(f"  [{flag:>4}] {name:<44} {n:>9,}  {desc}")
    return results


def export(con, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for fname, view in EXPORTS.items():
        con.execute(f"COPY (SELECT * FROM {view}) TO {_quote(out_dir / fname)} (HEADER, DELIMITER ',')")
        n = con.execute(f"SELECT count(*) FROM {view}").fetchone()[0]
        print(f"  wrote {out_dir / fname}  ({n:,} rows)")


def summary(con):
    q = """
        SELECT 'securities', count(DISTINCT secid)::VARCHAR FROM signals
        UNION ALL SELECT 'delisted securities', count(*)::VARCHAR FROM security_master WHERE delisted
        UNION ALL SELECT 'security-months', count(*)::VARCHAR FROM signals
        UNION ALL SELECT 'months', count(DISTINCT m)::VARCHAR FROM signals
        UNION ALL SELECT 'first month', min(m)::VARCHAR FROM signals
        UNION ALL SELECT 'last month', max(m)::VARCHAR FROM signals
        UNION ALL SELECT 'eligible names per month (avg)', round(avg(n), 1)::VARCHAR
                  FROM (SELECT m, count(*) n FROM eligible GROUP BY m)
        UNION ALL SELECT 'name-months with a composite', count(*)::VARCHAR FROM composite
        UNION ALL SELECT 'traded-days spread name-months', count(*)::VARCHAR FROM cs_traded
    """
    for k, v in con.execute(q).fetchall():
        print(f"  {k:<34} {v}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sources", required=True, help="TOML file mapping exports to paths")
    ap.add_argument("--db", default="sgx.duckdb", help="DuckDB file to (re)build")
    ap.add_argument("--export", metavar="DIR", help="also write the legacy-layout CSVs here")
    args = ap.parse_args()

    files, params = load_sources(args.sources)
    print(f"building {args.db}  (embargo {params['embargo_months']}m, stale after {params['stale_months']}m)")
    con = build(files, args.db, params)
    print("summary")
    summary(con)
    print("audits")
    failed = [r for r in run_audits(con) if r[1] == "fail" and r[2]]
    if args.export:
        export(con, args.export)
    if failed:
        sys.exit(f"{len(failed)} audit(s) failed")


if __name__ == "__main__":
    main()
