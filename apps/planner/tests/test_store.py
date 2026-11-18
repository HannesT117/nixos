import sqlite3

import pytest

from budget import PERIODS, Settings
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


def test_edit_of_row_deleted_elsewhere_raises_and_rolls_back(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    loaded = save_rows(conn, "expenses", [], [expense("a", 1), expense("b", 2)])
    save_rows(conn, "expenses", loaded, [loaded[1]])
    edited = [{**loaded[0], "amount": 7}, {**loaded[1], "amount": 8}]
    with pytest.raises(ValueError, match=f"expenses.*{loaded[0]['id']}"):
        save_rows(conn, "expenses", loaded, edited)
    assert [(r["name"], r["amount"]) for r in load(conn, "expenses")] == [("b", 2)]


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
        numeric = {"sacrifice_per_pay", "after_tax_per_pay", "annual"}
        row = {
            c: (2030 if c == "year" else 1.5 if c in numeric or c.endswith("_price") else "t")
            for c in TABLES[table]
        }
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


def test_schema_periods_match_budget_periods(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    for period in PERIODS:
        save_rows(conn, "expenses", [], [expense("a", 1, period=period)])
    assert len(load(conn, "expenses")) == len(PERIODS)
    with pytest.raises(sqlite3.IntegrityError):
        save_rows(conn, "expenses", [], [expense("a", 1, period="Daily")])


def _v1_db(path):
    conn = sqlite3.connect(path, isolation_level=None)
    conn.executescript(MIGRATIONS[0])
    conn.execute("PRAGMA user_version = 1")
    conn.execute("INSERT INTO scenarios (name, sacrifice_per_pay, after_tax_per_pay) VALUES ('s', 10, 20)")
    conn.execute("INSERT INTO expenses (name, amount, period) VALUES ('e', 5, 'Weekly')")
    conn.execute("INSERT INTO trips (dates, fuel_price) VALUES ('d', 7)")
    conn.execute("UPDATE settings SET yearly_gross = 90000, super_rate = 0.1 WHERE id = 1")
    conn.close()


def test_migration_2_keeps_v1_data(tmp_path):
    path = str(tmp_path / "p.sqlite")
    _v1_db(path)
    conn = connect(path)
    assert conn.execute("PRAGMA user_version").fetchone()[0] == 2
    scenarios = load(conn, "scenarios")
    assert [(r["name"], r["sacrifice_per_pay"], r["after_tax_per_pay"]) for r in scenarios] == [("s", 10, 20)]
    assert (scenarios[0]["year"], scenarios[0]["salary_step"]) == (None, None)
    assert [(r["name"], r["amount"]) for r in load(conn, "expenses")] == [("e", 5)]
    assert [(r["dates"], r["fuel_price"]) for r in load(conn, "trips")] == [("d", 7)]
    settings = load_settings(conn)
    assert (settings.yearly_gross, settings.super_rate, settings.pays_per_year) == (90000, 0.1, 26)
    assert (settings.salary_step, settings.include_leave_loading) == (None, None)
    assert load(conn, "salary_levels") == []


def level(step, effective_from, annual):
    return {"id": None, "step": step, "effective_from": effective_from, "annual": annual}


def test_save_rows_inserts_salary_levels(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    snap = save_rows(
        conn, "salary_levels", [], [level("A.1", "2030-01-01", 50000.0), level("A.2", "2030-01-01", 55000.0)]
    )
    assert load(conn, "salary_levels") == snap
    assert [(r["step"], r["effective_from"], r["annual"]) for r in snap] == [
        ("A.1", "2030-01-01", 50000.0),
        ("A.2", "2030-01-01", 55000.0),
    ]


@pytest.mark.parametrize(
    "rows",
    [
        [level("A.1", "2030-01-01", 50000.0), level("A.1", "2030-01-01", 51000.0)],
        [level("A.1", "2030-01-01", 0)],
        [level("A.1", "2030-01-01", -5)],
        [level("A.1", "1 Jan 2030", 50000.0)],
        [level("A.1", "2030-1-1", 50000.0)],
    ],
)
def test_salary_levels_reject_duplicates_and_bad_values(tmp_path, rows):
    conn = connect(str(tmp_path / "p.sqlite"))
    with pytest.raises(sqlite3.IntegrityError):
        save_rows(conn, "salary_levels", [], rows)
    assert load(conn, "salary_levels") == []


def test_scenario_year_range(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))

    def scenario(year):
        return {"id": None, "name": "s", "sacrifice_per_pay": 0, "after_tax_per_pay": 0, "year": year, "salary_step": None}

    with pytest.raises(sqlite3.IntegrityError):
        save_rows(conn, "scenarios", [], [scenario(1999)])
    snap = save_rows(conn, "scenarios", [], [scenario(None), scenario(2030)])
    assert [r["year"] for r in load(conn, "scenarios")] == [None, 2030]
    assert len(snap) == 2


def test_leave_loading_setting_round_trips_as_bool(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    assert load_settings(conn).include_leave_loading is None
    set_setting(conn, "include_leave_loading", True)
    assert load_settings(conn).include_leave_loading is True
    set_setting(conn, "include_leave_loading", False)
    assert load_settings(conn).include_leave_loading is False
    set_setting(conn, "salary_step", "A.1")
    assert load_settings(conn).salary_step == "A.1"
