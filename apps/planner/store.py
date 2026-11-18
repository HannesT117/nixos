import dataclasses
import os
import sqlite3

from budget import Settings

MIGRATIONS: list[str] = [
    """
CREATE TABLE scenarios (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
  sacrifice_per_pay REAL NOT NULL DEFAULT 0, after_tax_per_pay REAL NOT NULL DEFAULT 0);
CREATE TABLE expenses (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '', amount REAL NOT NULL DEFAULT 0,
  period TEXT NOT NULL DEFAULT 'Monthly'
    CHECK (period IN ('Weekly','Fortnightly','Monthly','Quarterly','Yearly')));
CREATE TABLE trips (id INTEGER PRIMARY KEY, dates TEXT, transport TEXT, transport_price REAL,
  insurance TEXT, insurance_price REAL, fuel TEXT, fuel_price REAL, accommodation TEXT, accommodation_price REAL);
CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK (id = 1), yearly_gross REAL, pays_per_year INTEGER,
  super_rate REAL, include_medicare_levy INTEGER, mls TEXT CHECK (mls IN ('none','single','family')),
  partner_income REAL, children INTEGER, savings_target_week REAL,
  weeks_per_trip REAL CHECK (weeks_per_trip > 0),
  baseline_scenario_id INTEGER REFERENCES scenarios(id) ON DELETE SET NULL);
INSERT INTO settings (id, pays_per_year) VALUES (1, 26);
"""
]

TABLES: dict[str, list[str]] = {
    "scenarios": ["name", "sacrifice_per_pay", "after_tax_per_pay"],
    "expenses": ["name", "amount", "period"],
    "trips": [
        "dates",
        "transport",
        "transport_price",
        "insurance",
        "insurance_price",
        "fuel",
        "fuel_price",
        "accommodation",
        "accommodation_price",
    ],
}

_SETTING_FIELDS = [f.name for f in dataclasses.fields(Settings)]


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    for number, script in enumerate(MIGRATIONS[version:], start=version + 1):
        try:
            conn.executescript(
                f"BEGIN;\n{script}\nPRAGMA user_version = {number};\nCOMMIT;"
            )
        except Exception:
            if conn.in_transaction:
                conn.execute("ROLLBACK")
            raise
    return conn


def open_from_env() -> sqlite3.Connection:
    path = os.environ.get("PLANNER_DB")
    if not path:
        raise SystemExit("PLANNER_DB is not set")
    return connect(path)


def _columns(table: str) -> list[str]:
    if table not in TABLES:
        raise ValueError(f"unknown table: {table}")
    return TABLES[table]


def load(conn: sqlite3.Connection, table: str) -> list[dict]:
    cols = ", ".join(["id", *_columns(table)])
    rows = conn.execute(f"SELECT {cols} FROM {table} ORDER BY id").fetchall()
    return [dict(r) for r in rows]


def _is_new(row: dict) -> bool:
    row_id = row.get("id")
    return not row_id or isinstance(row_id, bool) or not isinstance(row_id, int)


def save_rows(
    conn: sqlite3.Connection, table: str, loaded: list[dict], current: list[dict]
) -> list[dict]:
    cols = _columns(table)
    loaded_by_id = {r["id"]: r for r in loaded}
    kept_ids = {r["id"] for r in current if not _is_new(r)}
    unknown = kept_ids - loaded_by_id.keys()
    if unknown:
        raise ValueError(f"unknown row ids for {table}: {sorted(unknown)}")

    insert_sql = (
        f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})"
    )
    update_sql = f"UPDATE {table} SET {', '.join(f'{c} = ?' for c in cols)} WHERE id = ?"
    snapshot: list[dict] = []
    conn.execute("BEGIN")
    try:
        for row in current:
            values = [row.get(c) for c in cols]
            if _is_new(row):
                cursor = conn.execute(insert_sql, values)
                snapshot.append({**row, "id": cursor.lastrowid})
                continue
            before = loaded_by_id[row["id"]]
            if any(before.get(c) != row.get(c) for c in cols):
                conn.execute(update_sql, [*values, row["id"]])
            snapshot.append(dict(row))
        for removed in loaded_by_id.keys() - kept_ids:
            conn.execute(f"DELETE FROM {table} WHERE id = ?", (removed,))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    return snapshot


def load_settings(conn: sqlite3.Connection) -> Settings:
    row = dict(conn.execute("SELECT * FROM settings WHERE id = 1").fetchone())
    row.pop("id")
    if row["include_medicare_levy"] is not None:
        row["include_medicare_levy"] = bool(row["include_medicare_levy"])
    return Settings(**row)


def set_setting(conn: sqlite3.Connection, field: str, value) -> None:
    if field not in _SETTING_FIELDS:
        raise ValueError(f"unknown setting: {field}")
    if isinstance(value, bool):
        value = int(value)
    conn.execute(f"UPDATE settings SET {field} = ? WHERE id = 1", (value,))
