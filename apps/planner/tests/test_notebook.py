import os
import subprocess
import sys
from pathlib import Path

from budget import missing_settings, scenario_results
from store import connect, load_settings, save_rows, set_setting

APP_DIR = Path(__file__).resolve().parent.parent


def run(env):
    return subprocess.run(
        [sys.executable, "planner.py"], cwd=APP_DIR, env=env, capture_output=True
    )


def test_runs_on_empty_db(tmp_path):
    assert run({**os.environ, "PLANNER_DB": str(tmp_path / "p.sqlite")}).returncode == 0


def test_refuses_without_planner_db():
    env = {k: v for k, v in os.environ.items() if k != "PLANNER_DB"}
    assert run(env).returncode != 0


def test_runs_on_populated_db(tmp_path):
    path = str(tmp_path / "p.sqlite")
    conn = connect(path)
    scenarios = save_rows(
        conn,
        "scenarios",
        [],
        [
            {"id": None, "name": "Base", "sacrifice_per_pay": 0, "after_tax_per_pay": 0},
            {"id": None, "name": "Sacrifice", "sacrifice_per_pay": 200, "after_tax_per_pay": 50},
        ],
    )
    save_rows(
        conn,
        "expenses",
        [],
        [
            {"id": None, "name": "Rent", "amount": 500, "period": "Weekly"},
            {"id": None, "name": "Phone", "amount": 60, "period": "Monthly"},
        ],
    )
    save_rows(
        conn,
        "trips",
        [],
        [
            {"id": None, "dates": "Jan", "transport_price": 100, "insurance_price": 20,
             "fuel_price": 0, "accommodation_price": 300},
            {"id": None, "dates": "Feb", "transport_price": 120, "insurance_price": 20,
             "fuel_price": None, "accommodation_price": None},
        ],
    )
    for field, value in {
        "yearly_gross": 100000,
        "pays_per_year": 26,
        "super_rate": 0.12,
        "include_medicare_levy": True,
        "mls": "none",
        "savings_target_week": 300,
        "weeks_per_trip": 8,
        "baseline_scenario_id": scenarios[0]["id"],
    }.items():
        set_setting(conn, field, value)
    conn.close()
    result = run({**os.environ, "PLANNER_DB": path})
    assert result.returncode == 0, result.stderr.decode()


def test_runs_with_medicare_levy_false(tmp_path):
    path = str(tmp_path / "p.sqlite")
    conn = connect(path)
    save_rows(
        conn,
        "scenarios",
        [],
        [{"id": None, "name": "Base", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}],
    )
    for field, value in {
        "yearly_gross": 90000,
        "super_rate": 0.12,
        "include_medicare_levy": False,
        "mls": "none",
        "savings_target_week": 100,
        "weeks_per_trip": 8,
    }.items():
        set_setting(conn, field, value)
    settings = load_settings(conn)
    assert settings.include_medicare_levy is False
    assert missing_settings(settings) == []
    scenarios = [{"id": 1, "name": "Base", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}]
    assert len(scenario_results(scenarios, settings, 0)) == 1
    conn.close()
    result = run({**os.environ, "PLANNER_DB": path})
    assert result.returncode == 0, result.stderr.decode()
