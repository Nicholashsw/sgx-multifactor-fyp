import importlib.util
import sys
from pathlib import Path

import pandas as pd
import pytest

SQL_DIR = Path(__file__).resolve().parents[1]
CODE_DIR = SQL_DIR.parent / "code"
sys.path[:0] = [str(SQL_DIR), str(Path(__file__).resolve().parent)]

import build  # noqa: E402
from fixtures import write_exports  # noqa: E402


def load_code_module(name):
    """Import one of the project's pandas scripts from code/ by path."""
    spec = importlib.util.spec_from_file_location(name, CODE_DIR / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="session")
def exports(tmp_path_factory):
    return write_exports(tmp_path_factory.mktemp("exports"))


@pytest.fixture(scope="session")
def con(exports, tmp_path_factory):
    db = tmp_path_factory.mktemp("db") / "store.duckdb"
    c = build.build(exports, db, verbose=False)
    yield c
    c.close()


@pytest.fixture(scope="session")
def raw_secd(exports):
    return pd.read_csv(exports["secd"], dtype={"iid": str, "tpci": str, "isin": str, "sedol": str})
