import sqlite3

import pytest

from budget import Settings
from store import (
    MIGRATIONS,
    TABLES,
    connect,
    load,
    load_settings,
    open_from_env,
    save_rows,
    set_setting,
)


def expense(name, amount, period="Weekly", id=None):
    return {"id": id, "name": name, "amount": amount, "period": period}


def test_fresh_db_has_only_neutral_settings(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    assert load_settings(conn) == Settings(pays_per_year=26)
    assert all(load(conn, t) == [] for t in TABLES)


def test_reconnect_does_not_reapply_migrations(tmp_path):
    path = str(tmp_path / "p.sqlite")
    connect(path).close()
    conn = connect(path)
    assert conn.execute("PRAGMA user_version").fetchone()[0] == len(MIGRATIONS)
    assert load_settings(conn) == Settings(pays_per_year=26)


def test_open_from_env_requires_planner_db(monkeypatch):
    monkeypatch.delenv("PLANNER_DB", raising=False)
    with pytest.raises(SystemExit):
        open_from_env()


def test_open_from_env_rejects_empty(monkeypatch):
    monkeypatch.setenv("PLANNER_DB", "")
    with pytest.raises(SystemExit):
        open_from_env()


def test_open_from_env_opens_database(monkeypatch, tmp_path):
    monkeypatch.setenv("PLANNER_DB", str(tmp_path / "p.sqlite"))
    conn = open_from_env()
    assert load(conn, "expenses") == []


def test_save_rows_inserts_updates_deletes(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(conn, "expenses", [], [expense("a", 1), expense("b", 2)])
    assert all(isinstance(r["id"], int) for r in snap)
    updated = [{**snap[0], "amount": 5}]
    save_rows(conn, "expenses", snap, updated)
    rows = load(conn, "expenses")
    assert [(r["name"], r["amount"]) for r in rows] == [("a", 5)]


def test_inserted_row_is_not_inserted_twice(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(conn, "expenses", [], [expense("a", 1)])
    save_rows(conn, "expenses", snap, [{**snap[0], "amount": 5}])
    assert len(load(conn, "expenses")) == 1


def test_stale_editor_cannot_delete_rows_it_never_loaded(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    a = save_rows(conn, "expenses", [], [expense("x", 1)])
    stale = list(a)
    save_rows(conn, "expenses", a, a + [expense("y", 2)])
    save_rows(conn, "expenses", stale, [{**stale[0], "amount": 9}])
    assert sorted((r["name"], r["amount"]) for r in load(conn, "expenses")) == [
        ("x", 9),
        ("y", 2),
    ]


def test_unknown_id_raises(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    with pytest.raises(ValueError):
        save_rows(conn, "expenses", [], [expense("a", 1, id=42)])


def test_failed_save_rolls_back_everything(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    with pytest.raises(sqlite3.IntegrityError):
        save_rows(
            conn, "expenses", [], [expense("ok", 1), expense("bad", 2, period="Daily")]
        )
    assert load(conn, "expenses") == []


def test_invalid_period_rejected(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    with pytest.raises(sqlite3.IntegrityError):
        save_rows(conn, "expenses", [], [expense("a", 1, period="Daily")])


def test_extra_keys_in_current_rows_are_ignored(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(conn, "expenses", [], [{**expense("a", 1), "junk": 1}])
    save_rows(conn, "expenses", snap, [{**snap[0], "junk": 2}])
    assert len(load(conn, "expenses")) == 1


def test_unchanged_rows_are_not_rewritten(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(conn, "expenses", [], [expense("a", 1)])
    before = conn.total_changes
    save_rows(conn, "expenses", snap, list(snap))
    assert conn.total_changes == before


def test_trips_and_scenarios_round_trip(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    for table in ("trips", "scenarios"):
        row = {c: ("t" if c not in ("sacrifice_per_pay", "after_tax_per_pay") and not c.endswith("_price") else 1.5) for c in TABLES[table]}
        snap = save_rows(conn, table, [], [{"id": None, **row}])
        assert load(conn, table) == snap


def test_set_setting_changes_one_column_only(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    set_setting(conn, "yearly_gross", 100000.0)
    stale = load_settings(conn)
    set_setting(conn, "yearly_gross", 120000.0)
    set_setting(conn, "super_rate", 0.12)
    assert stale.yearly_gross == 100000.0
    now = load_settings(conn)
    assert (now.yearly_gross, now.super_rate) == (120000.0, 0.12)


def test_bool_setting_round_trips(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    assert load_settings(conn).include_medicare_levy is None
    set_setting(conn, "include_medicare_levy", True)
    assert load_settings(conn).include_medicare_levy is True
    set_setting(conn, "include_medicare_levy", False)
    assert load_settings(conn).include_medicare_levy is False
    set_setting(conn, "include_medicare_levy", None)
    assert load_settings(conn).include_medicare_levy is None


def test_unknown_setting_rejected(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    with pytest.raises(ValueError):
        set_setting(conn, "id; DROP TABLE settings", 1)


def test_deleting_baseline_clears_setting(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(
        conn,
        "scenarios",
        [],
        [{"id": None, "name": "s", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}],
    )
    set_setting(conn, "baseline_scenario_id", snap[0]["id"])
    assert load_settings(conn).baseline_scenario_id == snap[0]["id"]
    save_rows(conn, "scenarios", snap, [])
    assert load_settings(conn).baseline_scenario_id is None
