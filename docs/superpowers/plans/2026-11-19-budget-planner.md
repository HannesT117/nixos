# Budget Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Grist at money.jrdn.cx with a marimo budget planner, backed by SQLite on gmktec,
with a leak guard that keeps personal data out of git.

**Architecture:**
- Pure Python modules hold the domain: `tax.py` and `budget.py`.
- `store.py` is the only code that touches SQLite, with numbered migrations and per-row saves.
- A marimo notebook (`planner.py`) is only the UI.
- NixOS runs it as a static-user systemd service behind Caddy `forward_auth` (Authelia). An nftables
  rule lets only Caddy reach the port, and a daily backup goes to Syncthing.

**Tech Stack:** Python 3.14 in the service (nixpkgs), tests run locally on 3.13, marimo 0.25.1 (nixpkgs) / 0.25.2 (local dev), polars, SQLite, pytest,
NixOS (flake), Caddy, Authelia, nftables.

**Spec:** `docs/superpowers/specs/2026-11-18-budget-planner-design.md`

## Global Constraints

- No personal data in git: no real amounts, names of people or expense lines, tax circumstances,
  employer, or paths to local private files. This covers code, tests, migrations, docs and commit
  messages. Tests use the synthetic values in this plan only.
- Code never contains personal literals. Names and amounts come from the DB at runtime.
- No code comments unless the user approves them.
- Commit messages: `scope: imperative summary`, with no `feat`/`fix` prefix, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- nixos repo work happens on branch `planner/replace-grist`. Never commit in the server's
  `/etc/nixos` checkout.
- Static users, no DynamicUser. Persisted state goes in `nix/modules/impermanence.nix`.
- Periods are exactly `Weekly`, `Fortnightly`, `Monthly`, `Quarterly`, `Yearly`. Per-week factors:
  1, 1/2, 12/52, 4/52, 1/52. `WEEKS_PER_YEAR = 52`.
- marimo port `2719`, bound to `127.0.0.1`. The app exits non-zero if `PLANNER_DB` is unset.
- Local test command (from `apps/planner/`):
  `uv run -q --python 3.13 --no-project --with pytest --with marimo==0.25.2 --with polars pytest`

## Review Focus

1. **Settings not filled in yet** (fresh DB, all personal fields NULL). The Overview shows
   "Complete the settings: …" and no results, with no traceback. → Task 3
   `test_scenario_results_requires_complete_settings`; Task 5 smoke test on an empty DB.
2. **Empty tables** (no trips, no expenses, no scenarios). Totals are 0, the trip average is 0, and
   the scenario list is empty. → Task 3 `test_empty_inputs_give_zeros`.
3. **Baseline scenario deleted.** `baseline_scenario_id` becomes NULL through the foreign key, and
   the takehome reduction is `None` (shown as "—"), not a crash. → Task 4
   `test_deleting_baseline_clears_setting`; Task 3 `test_takehome_reduction_without_baseline`.
4. **Blank cells in the trips grid** (a price left empty). The trip total treats it as 0. Fuel left
   empty means not done; 0 means done. → Task 3 `test_trip_total_and_done_with_blanks`.
5. **Sacrifice larger than gross** (negative taxable). Total tax is 0, and there's no negative
   Medicare levy. → Task 2 `test_negative_taxable_pays_no_tax`.

---

### Task 1: Leak guard

**Files:**
- Create: `~/dotfiles/shared/bin/private-terms-guard` (Python 3.9+, stdlib only, executable)
- Create: `~/dotfiles/shared/bin/tests/test_private_terms_guard.py`
- Create (untracked): the hooks in `~/dev/projects/nixos/.git/hooks/` and `~/dotfiles/.git/hooks/`:
  `pre-commit`, `commit-msg`, `pre-push`. Each is a one-line `exec` of the guard with its mode.
- Create (outside every repo): `~/.local/share/private-terms`, empty, mode 0600.
- Modify: `.gitignore` in both repos, adding `*.sqlite *.db *.numbers *.csv *.xlsx`.

**Interfaces:**
- Produces: the CLI `private-terms-guard {pre-commit | commit-msg <file> | pre-push}`. Exit 0 = OK;
  exit 1 = blocked, printing `file:line` and the *kind* of match ("deny-listed term #N"), never
  the term itself. The list path is fixed at `~/.local/share/private-terms`; the env var
  `PRIVATE_TERMS_FILE` overrides it, for tests only.
- Python functions the tests import (load the script with `importlib.machinery.SourceFileLoader`):
  - `normalise(text: str) -> str`: lowercases; inside digit runs, removes `,`, `_` and spaces;
    strips a trailing `.0` or `.00` after digits.
  - `load_terms(path: Path) -> list[str]`: raises `SystemExit(1)` if the file is missing or
    empty, or if `git -C <resolved parent> rev-parse --show-toplevel` succeeds (the list is inside
    a work tree).
  - `find_hits(text: str, terms: list[str]) -> list[int]`: 1-based line numbers whose normalised
    text contains any normalised term.
  - `blocked_paths(paths: list[str]) -> list[str]`: paths that end in a data-file extension.

- [ ] **Step 1: Write the failing tests** (synthetic terms only)

```python
def test_normalise_matches_number_formats():
    assert normalise("rent 1,234.00") == normalise("rent 1234") == normalise("RENT 1_234")

def test_find_hits_reports_line_numbers():
    assert find_hits("a\nfoo 98,765\nb", ["98765"]) == [2]

def test_missing_or_empty_list_fails_closed(tmp_path):
    with pytest.raises(SystemExit):
        load_terms(tmp_path / "absent")
    (tmp_path / "empty").write_text("\n")
    with pytest.raises(SystemExit):
        load_terms(tmp_path / "empty")

def test_list_inside_git_work_tree_is_rejected(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "terms").write_text("zebrafish\n")
    with pytest.raises(SystemExit):
        load_terms(tmp_path / "terms")

def test_data_files_are_blocked():
    assert blocked_paths(["a/b.sqlite", "x.py", "c.numbers"]) == ["a/b.sqlite", "c.numbers"]

def test_pre_commit_blocks_staged_term(tmp_path):
    ...  # git init a temp repo, stage a file containing "zebrafish 4,321", run the script with
         # PRIVATE_TERMS_FILE pointing at a list outside that repo containing "4321"; expect exit 1
         # and stdout not containing "4321"
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `cd ~/dotfiles/shared/bin && uv run -q --no-project --with pytest pytest tests -q`
Expected: FAIL, because the script doesn't exist yet.

- [ ] **Step 3: Implement `private-terms-guard`**

The script loads its terms once, through `load_terms`. Each mode then checks:
- `pre-commit`: the added lines of `git diff --cached -U0`, plus `blocked_paths` on
  `git diff --cached --name-only`.
- `commit-msg <file>`: the message file.
- `pre-push`: read the `<local ref> <local sha> <remote ref> <remote sha>` lines from stdin. For
  each, check `git log -p <remote sha>..<local sha>`, or `<local sha> --not --remotes` when the
  remote sha is all zeros. That covers patches and messages, and runs `blocked_paths` on the names.

- [ ] **Step 4: Run the tests and confirm they pass**

Run the Step 2 command. Expected: all pass.

- [ ] **Step 5: Install the hooks and the empty list, then stop for the user**

Write the three hook files in both repos (`#!/bin/sh` +
`exec ~/dotfiles/shared/bin/private-terms-guard <mode> "$@"`, chmod +x). Create the empty list
file. Check: `git -C ~/dev/projects/nixos commit --allow-empty -m test` must be **blocked** with
"term list is empty".

Then tell the user to fill in `~/.local/share/private-terms` (one term per line): names, amounts,
employer, and the figures in the local script's usage examples and `--super-rate` help. **Wait for
them to confirm before going on.** Don't guess the terms, and don't read the list.

- [ ] **Step 6: Commit (dotfiles), then the spec and this plan (nixos)**

```bash
cd ~/dotfiles && git add shared/bin/private-terms-guard shared/bin/tests .gitignore && git commit -m "git: add private-terms guard for commits and pushes"
cd ~/dev/projects/nixos && git switch -c planner/replace-grist && git add .gitignore docs/superpowers && git commit -m "planner: add design and implementation plan"
```

Expected: both commits pass the guard. If one is blocked, show the user the reported line and fix
the content. Never bypass the guard.

---

### Task 2: `tax.py`

**Files:**
- Create: `apps/planner/pytest.ini` (`[pytest]`, `pythonpath = .`, `testpaths = tests`)
- Create: `apps/planner/tax.py`
- Test: `apps/planner/tests/test_tax.py`

**Interfaces:**
- Produces:
  - `RATES: dict`. Statutory 2026-27 values, keys as follows:

    | Key | Value |
    |---|---|
    | `tax_brackets` | `[(0, 0.0), (18_200, 0.15), (45_000, 0.30), (135_000, 0.37), (190_000, 0.45)]` |
    | `medicare_levy` | 0.02 |
    | `lito_max` | 700 |
    | `lito_full_until` | 37_500 |
    | `lito_mid_until` | 45_000 |
    | `lito_mid_value` | 325 |
    | `lito_zero_at` | 66_667 |
    | `lito_taper_1` | 0.05 |
    | `lito_taper_2` | 0.015 |
    | `mls_single` | `[(105_000, 0.0), (123_000, 0.01), (164_000, 0.0125), (inf, 0.015)]` |
    | `mls_family` | `[(210_000, 0.0), (246_000, 0.01), (328_000, 0.0125), (inf, 0.015)]` |
    | `mls_family_extra_per_child` | 1_500 |
    | `concessional_cap` | 32_500 |
    | `contributions_tax` | 0.15 |
    | `fhss_year_limit` | 15_000 |
    | `fhss_concessional_share` | 0.85 |
  - `@dataclass(frozen=True) class TaxSettings`: `include_medicare_levy: bool`, `mls: str`
    (`"none" | "single" | "family"`), `partner_income: float`, `children: int`.
  - `@dataclass(frozen=True) class TaxResult`: `gross_tax`, `lito`, `medicare`, `mls_income`,
    `mls_rate`, `mls`, `total` (all `float`).
  - `def tax(taxable: float, sacrifice_year: float, s: TaxSettings) -> TaxResult`
- Write the module fresh. Copy no text, examples or defaults from the local script.

- [ ] **Step 1: Write the failing tests.** These are synthetic cases, with expected values
  produced by the local script on 2026-11-19:

```python
CASES = [  # name, taxable, sacrifice, levy, mls, partner, children, gross, lito, medicare, mls_rate, mls, total
    ("low", 15000, 0, False, "none", 0, 0, 0.00, 0.00, 0.00, 0.0, 0.00, 0.00),
    ("lito_taper_1", 40000, 0, False, "none", 0, 0, 3270.00, 575.00, 0.00, 0.0, 0.00, 2695.00),
    ("lito_taper_2", 60000, 0, True, "none", 0, 0, 8520.00, 100.00, 1200.00, 0.0, 0.00, 9620.00),
    ("bracket_37", 150000, 0, True, "none", 0, 0, 36570.00, 0.00, 3000.00, 0.0, 0.00, 39570.00),
    ("bracket_45", 200000, 0, False, "none", 0, 0, 55870.00, 0.00, 0.00, 0.0, 0.00, 55870.00),
    ("mls_single_edge", 105000, 0, False, "single", 0, 0, 22020.00, 0.00, 0.00, 0.0, 0.00, 22020.00),
    ("mls_single_over", 100000, 5001, False, "single", 0, 0, 20520.00, 0.00, 0.00, 0.01, 1000.00, 21520.00),
    ("mls_family_kids", 90000, 10000, True, "family", 130000, 3, 17520.00, 0.00, 1800.00, 0.01, 900.00, 20220.00),
]

@pytest.mark.parametrize("case", CASES, ids=[c[0] for c in CASES])
def test_tax_matches_reference(case): ...  # each field equals expected within 0.01

def test_negative_taxable_pays_no_tax():
    r = tax(-1000, 0, TaxSettings(True, "single", 0, 0))
    assert (r.gross_tax, r.medicare, r.mls, r.total) == (0, 0, 0, 0)
```

- [ ] **Step 2: Run them and confirm they fail.** Use the Global Constraints test command with
  `tests/test_tax.py`. Expected: ImportError.

- [ ] **Step 3: Implement `tax.py`.**
  - Gross tax sums `(min(taxable, upper) − lower) × rate` over the brackets.
  - LITO is `min(gross_tax, offset)`, where offset is:
    - `lito_max` up to `lito_full_until`;
    - then `lito_max − (t − lito_full_until) × lito_taper_1` up to `lito_mid_until`;
    - then `max(0, lito_mid_value − (t − lito_mid_until) × lito_taper_2)` up to `lito_zero_at`;
    - else 0.
  - MLS income = taxable + sacrifice + (partner income if family).
  - The MLS tier limit is raised by `(children − 1) × extra` for a family with more than 1 child.
    The rate is that of the first tier whose limit is ≥ the MLS income.
  - Clamp taxable at 0 for the Medicare and MLS amounts.

- [ ] **Step 4: Run them and confirm they pass.**

- [ ] **Step 5: Commit:** `git commit -m "planner: add tax rules with reference cases"`

---

### Task 3: `budget.py`

**Files:**
- Create: `apps/planner/budget.py`
- Test: `apps/planner/tests/test_budget.py`

**Interfaces:**
- Consumes: `tax.RATES`, `tax.TaxSettings`, `tax.tax`.
- Produces:
  - `PERIODS: dict[str, float]` (Global Constraints) and `WEEKS_PER_YEAR = 52`.
  - `def per_week(amount: float, period: str) -> float`. Raises `ValueError` for an unknown period.
  - `def trip_total(trip: Mapping) -> float`. Sums `transport_price`, `insurance_price`,
    `fuel_price` and `accommodation_price`; a missing key or `None` counts as 0.
  - `def is_done(trip: Mapping) -> bool`: `trip.get("fuel_price") is not None`.
  - `@dataclass(frozen=True) TripSummary(done_trips: int, average_trip: float, trips_week: float)`
    and `def trip_summary(trips: list[Mapping], weeks_per_trip: float) -> TripSummary`.
  - `@dataclass(frozen=True) ExpenseTotals(recurring_week: float, trips_week: float, total_week: float)`
    and `def expense_totals(expenses: list[Mapping], trips_week: float) -> ExpenseTotals`.
  - `@dataclass(frozen=True) Settings`: `yearly_gross`, `pays_per_year`, `super_rate`,
    `include_medicare_levy`, `mls`, `partner_income`, `children`, `savings_target_week`,
    `weeks_per_trip`, `baseline_scenario_id`. All are `Optional`, all default to `None`.
  - `def missing_settings(s: Settings) -> list[str]`. Always required: `yearly_gross`,
    `pays_per_year`, `super_rate`, `include_medicare_levy`, `mls`, `savings_target_week`,
    `weeks_per_trip`. Also `partner_income` and `children` when `mls == "family"`.
  - `@dataclass(frozen=True) ScenarioResult` with these fields (`float` unless noted):
    `id: int`, `name: str`, `sacrifice_year`, `after_tax_year`, `taxable`, `gross_tax`, `lito`,
    `medicare`, `mls_rate`, `mls`, `total_tax`, `net_year`, `net_week`,
    `takehome_reduction_week: float | None`, `super_gain_year`, `super_gain_week`,
    `employer_super`, `concessional_total`, `cap_left`, `fhss_release`, `expenses_week`,
    `cash_savings_week`, `rest_week`.
  - `def scenario_results(scenarios: list[Mapping], s: Settings, total_week: float) -> list[ScenarioResult]`.
    Raises `ValueError` listing the fields from `missing_settings` if any are missing.

- [ ] **Step 1: Write the failing tests.**

```python
def test_per_week_factors():
    assert [round(per_week(52, p), 2) for p in PERIODS] == [52, 26, 12, 4, 1]

def test_unknown_period_raises():
    with pytest.raises(ValueError):
        per_week(10, "Daily")

def test_trip_total_and_done_with_blanks():
    t = {"transport_price": 100, "insurance_price": None, "fuel_price": 0, "accommodation_price": 50}
    assert trip_total(t) == 150 and is_done(t)
    assert not is_done({**t, "fuel_price": None})

def test_trip_summary_averages_done_trips_only():
    trips = [{"transport_price": 100, "fuel_price": 50}, {"transport_price": 200, "fuel_price": 0},
             {"transport_price": 999, "fuel_price": None}]
    assert trip_summary(trips, 2) == TripSummary(2, 175, 87.5)

def test_empty_inputs_give_zeros():
    assert trip_summary([], 2) == TripSummary(0, 0, 0)
    assert expense_totals([], 0) == ExpenseTotals(0, 0, 0)

def test_expense_totals_add_trips():
    e = [{"amount": 100, "period": "Weekly"}, {"amount": 520, "period": "Yearly"}]
    assert expense_totals(e, 30) == ExpenseTotals(110, 30, 140)

def test_scenario_results_requires_complete_settings():
    with pytest.raises(ValueError, match="yearly_gross"):
        scenario_results([], Settings(), 0)

SETTINGS = Settings(yearly_gross=80_000, pays_per_year=26, super_rate=0.12, include_medicare_levy=False,
                    mls="none", savings_target_week=200, weeks_per_trip=2, baseline_scenario_id=1)

def test_scenario_matches_tax_module_and_rules():
    [base, s100] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0},
                                     {"id": 2, "name": "b", "sacrifice_per_pay": 100, "after_tax_per_pay": 50}],
                                    SETTINGS, 500)
    expected_tax = tax(80_000 - 2600, 2600, TaxSettings(False, "none", 0, 0)).total
    assert s100.net_year == pytest.approx(80_000 - 2600 - expected_tax - 1300)
    assert s100.super_gain_week == pytest.approx((2600 * 0.85 + 1300) / 52)
    assert s100.cash_savings_week == pytest.approx(max(0, 200 - s100.super_gain_week))
    assert s100.rest_week == pytest.approx(s100.net_week - 500 - s100.cash_savings_week)
    assert s100.employer_super == 9600 and s100.concessional_total == 12_200
    assert s100.cap_left == 20_300
    assert s100.fhss_release == pytest.approx(2600 * 0.85 + 1300)
    assert s100.takehome_reduction_week == pytest.approx((base.net_year - s100.net_year) / 52)

def test_takehome_reduction_without_baseline():
    [r] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}],
                           replace(SETTINGS, baseline_scenario_id=None), 0)
    assert r.takehome_reduction_week is None
```

- [ ] **Step 2: Run them and confirm they fail.** Expected: ImportError.
- [ ] **Step 3: Implement `budget.py`.**
  - FHSS release = `min(sacrifice_y, limit) × share + min(after_tax_y, limit − min(sacrifice_y, limit))`.
  - Employer super = gross × super rate.
- [ ] **Step 4: Run them and confirm they pass** (all of `tests/`).
- [ ] **Step 5: Commit:** `git commit -m "planner: add budget calculations"`

---

### Task 4: `store.py`

**Files:**
- Create: `apps/planner/store.py`
- Test: `apps/planner/tests/test_store.py`

**Interfaces:**
- Consumes: `budget.Settings`, `budget.PERIODS`.
- Produces:
  - `MIGRATIONS: list[str]`. Each entry is one SQL script. Entry 1:

```sql
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
```

  - `def connect(path: str) -> sqlite3.Connection`. Sets `row_factory = sqlite3.Row`,
    `PRAGMA foreign_keys = ON`, and applies `MIGRATIONS[user_version:]`, each in a transaction
    that also bumps `user_version`.
  - `def open_from_env() -> sqlite3.Connection`. Raises `SystemExit("PLANNER_DB is not set")` if
    `PLANNER_DB` is unset or empty.
  - `TABLES = {"scenarios": [...], "expenses": [...], "trips": [...]}`: the editable column names.
  - `def load(conn, table: str) -> list[dict]`. Rows include `id`, ordered by `id`.
  - `def save_rows(conn, table: str, loaded: list[dict], current: list[dict]) -> list[dict]`.
    It diffs `current` against `loaded`:
    - a row whose `id` is falsy or not an int → `INSERT`;
    - a row whose `id` is in `loaded` and whose values changed → `UPDATE`;
    - an `id` in `loaded` but not in `current` → `DELETE`;
    - an `id` in neither → `ValueError`.

    It returns the new snapshot (`current` with the inserted ids filled in). It never touches ids
    outside `loaded`.
  - `def load_settings(conn) -> Settings` (bools come back as `bool`).
  - `def set_setting(conn, field: str, value) -> None`. Updates one column. Raises `ValueError` for
    a field that isn't in `Settings`.

- [ ] **Step 1: Write the failing tests** (temp DB via `tmp_path`):

```python
def test_fresh_db_has_only_neutral_settings(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    assert load_settings(conn) == Settings(pays_per_year=26)
    assert all(load(conn, t) == [] for t in TABLES)

def test_reconnect_does_not_reapply_migrations(tmp_path): ...  # connect twice; user_version == len(MIGRATIONS)

def test_open_from_env_requires_planner_db(monkeypatch):
    monkeypatch.delenv("PLANNER_DB", raising=False)
    with pytest.raises(SystemExit):
        open_from_env()

def test_save_rows_inserts_updates_deletes(tmp_path): ...
    # insert two expenses via save_rows([], [...]); snapshot ids are ints; then update one and
    # delete the other via save_rows(snapshot, ...); load() reflects exactly that

def test_inserted_row_is_not_inserted_twice(tmp_path): ...
    # snap = save_rows([], [new]); save_rows(snap, [{**snap[0], "amount": 5}]); len(load()) == 1

def test_stale_editor_cannot_delete_rows_it_never_loaded(tmp_path):
    conn = connect(str(tmp_path / "p.sqlite"))
    a = save_rows(conn, "expenses", [], [{"id": None, "name": "x", "amount": 1, "period": "Weekly"}])
    stale = list(a)
    save_rows(conn, "expenses", a, a + [{"id": None, "name": "y", "amount": 2, "period": "Weekly"}])
    save_rows(conn, "expenses", stale, [{**stale[0], "amount": 9}])
    assert sorted((r["name"], r["amount"]) for r in load(conn, "expenses")) == [("x", 9), ("y", 2)]

def test_invalid_period_rejected(tmp_path): ...  # sqlite3.IntegrityError

def test_set_setting_changes_one_column_only(tmp_path): ...
    # set yearly_gross, then set super_rate from a "stale" Settings view; yearly_gross is kept

def test_deleting_baseline_clears_setting(tmp_path): ...
    # insert scenario, set_setting("baseline_scenario_id", id), delete via save_rows -> load_settings().baseline_scenario_id is None
```

- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement `store.py`.** Table and column names come only from `TABLES` and
  `Settings` fields; values are always bound as parameters.
- [ ] **Step 4: Run them and confirm they pass** (all of `tests/`).
- [ ] **Step 5: Commit:** `git commit -m "planner: add SQLite store with migrations and per-row saves"`

---

### Task 5: `planner.py` (marimo UI)

**Files:**
- Create: `apps/planner/planner.py` (a marimo notebook with a PEP 723 header:
  `requires-python = ">=3.12"`, `dependencies = ["marimo==0.25.2", "polars"]`)
- Test: `apps/planner/tests/test_notebook.py`

**Interfaces:**
- Consumes: everything above. The notebook holds no calculations of its own.
- UI structure (from the spec):
  - **Tabs:** Overview, Expenses, Trips, Settings, Tax details.
  - **Expenses:** a form list (`mo.ui.array` of `mo.ui.dictionary`: `mo.ui.text`, `mo.ui.number`,
    `mo.ui.dropdown(list(PERIODS))`), with per-row Delete and an "Add expense" button.
  - **Trips and scenarios:** `mo.ui.data_editor` with `editable_columns` = all except `id`.
  - **Settings:**
    - number inputs for the numeric settings;
    - a switch for the Medicare levy;
    - dropdowns for MLS and for the baseline (scenario names → ids);
    - each control's `on_change` calls `set_setting` for its own field.
  - **Overview:**
    - if `missing_settings` is non-empty: `"Complete the settings: <labels>"` instead of results;
    - otherwise the scenario table, or one `mo.stat` card per scenario when there are more than 3
      columns' worth on a narrow screen (implementer's choice of breakpoint mechanism);
    - cards for Recurring / Trips / Total per week, and the trip cards;
    - `takehome_reduction_week is None` is shown as "—".
  - Amounts are shown as `$1,234.56`.
  - Each editor keeps its snapshot in `mo.state(load(...), allow_self_loops=True)`. `on_change`
    calls `save_rows(conn, table, snapshot, current)` and stores the returned snapshot.
    - Add and Delete build `current` from the form's live `.value`, never from a captured list.
      The spike lost an edit exactly that way.

- [ ] **Step 1: Write the failing smoke tests:**

```python
def run(env): return subprocess.run([sys.executable, "planner.py"], cwd=APP_DIR, env=env, capture_output=True)

def test_runs_on_empty_db(tmp_path):
    assert run({**os.environ, "PLANNER_DB": str(tmp_path / "p.sqlite")}).returncode == 0

def test_refuses_without_planner_db():
    env = {k: v for k, v in os.environ.items() if k != "PLANNER_DB"}
    assert run(env).returncode != 0

def test_runs_on_populated_db(tmp_path): ...
    # seed via store: 2 synthetic scenarios, 2 expenses, 2 trips, complete Settings; returncode == 0
```

- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement `planner.py`.** Check that the notebook imports `tax`, `budget` and
  `store` when it is started from a different cwd (`marimo run /abs/path/planner.py`). If not,
  insert `mo.notebook_dir()` into `sys.path` in the first cell.
- [ ] **Step 4: Run the tests and confirm they pass.** Then try it by hand:
  `PLANNER_DB=$TMPDIR/p.sqlite uv run ... marimo run planner.py --headless --port 2719`. Check:
  - with empty settings, the "Complete the settings" message appears;
  - after filling in the settings and adding a synthetic expense, a trip with fuel 0 and two
    scenarios, the totals add up;
  - after a reload, everything is still there;
  - two tabs: add a row in one, edit another row in the other; both survive;
  - at 375px width the cards wrap and the Overview has no horizontal scroll.
- [ ] **Step 5: Commit:** `git commit -m "planner: add marimo UI"`

---

### Task 6: NixOS service, replacing Grist

**Files:**
- Create: `nix/services/planner.nix`
- Delete: `nix/services/grist.nix`
- Modify: `nix/hosts/gmktec/default.nix:20` (`grist.nix` → `planner.nix`)
- Modify: `nix/modules/impermanence.nix:69` (`"/var/lib/grist-core"` →
  `{ directory = "/var/lib/planner"; user = "planner"; group = "planner"; mode = "0700"; }`)
- Modify: `nix/services/reverse-proxy.nix`. Delete the `let grist = …; in` binding (lines 3-5)
  and the `money.jrdn.cx` vhost (lines 32-49).
- Modify: `README.md:20` (`| Grist | money.jrdn.cx | — |` → `| Planner | money.jrdn.cx | — |`)

**Interfaces (`planner.nix`):**
- `let port = "2719"; app = ../../apps/planner; python = pkgs.python3.withPackages (ps: [ ps.marimo ps.polars ]); in`
- `users.users.planner` (`isSystemUser`, `group = "planner"`, `home = "/var/lib/planner"`) and
  `users.groups.planner`.
- `systemd.services.planner`:
  - `wantedBy = [ "multi-user.target" ]`, `after = [ "network.target" ]`;
  - `environment`: `PLANNER_DB = "/var/lib/planner/planner.sqlite"`, `HOME = "/var/lib/planner"`,
    and `XDG_CONFIG_HOME`/`XDG_CACHE_HOME` under it;
  - `ExecStart = "${python}/bin/marimo run ${app}/planner.py --headless --host 127.0.0.1 --port ${port}"`;
  - `User`/`Group = "planner"`, `StateDirectory = "planner"`, `StateDirectoryMode = "0700"`;
  - hardening from `rex.nix:23-32` (without the `IPAddress*` lines), and
    `InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/planner"`.
- `services.caddy.virtualHosts."money.jrdn.cx".extraConfig`. This lives in `planner.nix`, so the
  port has one source:

```
forward_auth localhost:9091 {
  uri /api/authz/forward-auth
  copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
}
reverse_proxy localhost:${port}
```

- `networking.nftables.tables.planner-local`. Same shape as the deleted `grist.nix` table, with
  `localClients = "meta skuid != caddy"`. Set `networking.nftables.preCheckRuleset` to the sed that
  swaps it for `meta skuid != root`.
- `systemd.services.planner-backup` (oneshot, root, `path = [ pkgs.sqlite pkgs.coreutils ]`) and
  `systemd.timers.planner-backup` (`OnCalendar = "daily"`, `Persistent = true`,
  `RandomizedDelaySec = "1h"`). The script:
  - runs `sqlite3 /var/lib/planner/planner.sqlite ".backup '/var/lib/syncthing/planner-backup/<ISO timestamp>.sqlite'"`;
  - deletes all but the newest 30;
  - runs `chown -R syncthing:syncthing` on the directory.

- [ ] **Step 1: Make the changes above.** First check that `/var/lib/syncthing` is persisted in
  `impermanence.nix`, and that nothing else references `services.grist` (`git grep -n grist nix`
  should be empty afterwards).
- [ ] **Step 2: Evaluate locally:**

  Run: `nix eval .#nixosConfigurations.gmktec.config.system.build.toplevel.drvPath`
  Expected: a `.drv` path, no error. If evaluation needs `NIXPKGS_ALLOW_BROKEN=1 --impure` on
  darwin (as `authelia` did before), that's acceptable, but say so.

  Run: `nix eval --raw '.#nixosConfigurations.gmktec.config.services.caddy.virtualHosts."money.jrdn.cx".extraConfig'`
  Expected: the block above with `2719`, and no `Bearer` or `_logout`.
- [ ] **Step 3: Commit:** `git commit -m "planner: serve at money.jrdn.cx and remove grist"`

---

### Task 7: Deploy, import and server checks (with the user)

Each step needs the user. They run the server commands. Claude runs nothing on the server and
never handles real values.

- [ ] **Step 1:** Push the branch and merge it to `main`, only after the user says so. Then, on the
  server: `cd /etc/nixos && git pull`, `sudo nixos-rebuild build --flake /etc/nixos#gmktec`, then
  `sudo nixos-rebuild switch --flake /etc/nixos#gmktec`. Expected: `planner.service` is active,
  and `nft list table inet planner-local` shows the rule.
- [ ] **Step 2: Server checks.** Each command and its expected result:

  | Command | Expected |
  |---|---|
  | `curl -sI https://money.jrdn.cx` | 302 to auth.jrdn.cx |
  | `curl -sI -H 'Authorization: Bearer x' https://money.jrdn.cx` | 302 to auth.jrdn.cx |
  | `sudo -u nobody curl -s 127.0.0.1:2719` | connection reset |
  | `journalctl -u planner` | no write errors under the Nix store |

  Then log in on a phone: the app shows "Complete the settings".
- [ ] **Step 3: Import (local, untracked).**
  - The user describes how their spreadsheet maps onto `scenarios`, `expenses`, `trips` and
    `settings`. Two points to settle there:
    - amounts that used to be added to the trip average become ordinary expenses, with their
      period chosen then;
    - a trip that is done but has no fuel price gets fuel 0.
  - Claude writes the import script in the user's local, untracked working folder. It contains no literals, reads the
    spreadsheet, takes personal settings as CLI arguments, writes through `store.connect` to
    `$TMPDIR/planner.sqlite`, and prints only counts.
  - The user runs it, then copies the file across: `scp` to the server,
    `sudo install -o planner -g planner -m 0600 … /var/lib/planner/planner.sqlite`,
    `sudo systemctl restart planner`, and deletes the local copy.
- [ ] **Step 4: Cleanup on the server:**
  `sudo rm -rf /persist/var/lib/grist-core /persist/secrets/grist-env`.
- [ ] **Step 5: Backups.**
  - Run `sudo systemctl start planner-backup`.
  - The user adds `/var/lib/syncthing/planner-backup` as a folder in the Syncthing UI and shares it
    with their device.
  - Expected: the backup file arrives on that device.
- [ ] **Step 6: Reboot.** Expected: the data survives, and `nft list ruleset` still contains
  `planner-local`.
- [ ] **Step 7: Open question from the spec.** Log in, open the app, and let the Authelia session
  expire (or log out in another tab). Does the open tab keep working? Report the result to the
  user and let them decide whether it's acceptable.
- [ ] **Step 8: Retire local files** (the user confirms each): the local salary-sacrifice script,
  the local Grist scripts, the local spike, the import script and the migrated
  spreadsheet tables.
