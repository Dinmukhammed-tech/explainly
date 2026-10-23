"""Tests run on a separate database, so they never touch your real subjects."""

import os

import psycopg
import pytest

TEST_DB = "explainly_test"
ADMIN = "postgresql://explainly:explainly@localhost:5433/explainly"

os.environ["DATABASE_URL"] = f"postgresql+psycopg://explainly:explainly@localhost:5433/{TEST_DB}"
os.environ["LLM_API_KEY"] = ""  # tests never call a paid API
os.environ["WARM_UP"] = "0"

with psycopg.connect(ADMIN, autocommit=True) as conn:
    if not conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (TEST_DB,)).fetchone():
        conn.execute(f"CREATE DATABASE {TEST_DB}")


@pytest.fixture()
def client():
    from fastapi.testclient import TestClient

    from app.db import Base, engine, init_db
    from app.main import app

    init_db()
    Base.metadata.drop_all(engine)
    with TestClient(app) as test_client:
        yield test_client
