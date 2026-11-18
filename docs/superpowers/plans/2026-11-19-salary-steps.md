# Salary Steps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the salary from an imported pay scale (step + date), add leave loading, and let each scenario set a year and a step.

**Architecture:** The pay scale is data: a new `salary_levels` table filled by the local import. `budget.py` gets the new rules as pure functions. `store.py` gets migration 2. `planner.py` gets the new controls and columns. No Nix changes.

**Tech Stack:** Python 3.13 locally (3.14 in the service), marimo 0.25.2 / 0.25.1, polars, SQLite, pytest.

**Spec:** `docs/superpowers/specs/2026-11-18-budget-planner-design.md`. See the section "Addendum (2026-11-19): salary steps, leave loading, scenario year" and the original anti-goals.

## Global Constraints

- **No personal data in git.** This covers real amounts, steps, names, employer, tax circumstances and private paths, in code, tests, migrations, docs and commit messages. Tests use synthetic steps (`A.1`, `A.2`) and synthetic amounts only.
- **Code wording.** The code says "salary step" and "pay scale". It never names an employer or a sector-specific grade name.
- **Comments.** No code comments unless the user approves them.
- **Commit messages.** Format: `scope: imperative summary`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Where work happens.** Work in the `planner/salary-steps` worktree (branch `planner/salary-steps`) and nowhere else.
- **Migrations.** They are append-only. `MIGRATIONS[0]` must not change.
- **Leave loading.** It is `annual / 52 * 4 * 0.175`. It is added to taxable income. Employer super is `salary * super_rate`, where salary excludes the loading.
- **Reference date.** `date(year, 3, 1)` when the scenario has a year, today otherwise.
- **Choosing the salary.**
  - The step is the scenario's `salary_step`, or failing that the Settings `salary_step`.
  - With no step at all, the salary is the manual `yearly_gross`.
  - For a step, the salary is the rate with the latest `effective_from` that is on or before the reference date.
- **Errors.** An unknown step, or a step with no rate on or before the reference date, raises `ValueError`. It never becomes $0. The UI shows it as a danger callout, never a traceback.
- **Tests.** From `apps/planner/`, run: `uv run -q --python 3.13 --no-project --with pytest --with marimo==0.25.2 --with polars pytest`.

## Review Focus

1. **Existing DB at version 1.** This is the live server DB. Migration 2 keeps every row, and the new columns start NULL. Test: Task 1 `test_migration_2_keeps_v1_data`.
2. **Settings that were complete before.** They now need `include_leave_loading`, which starts NULL. The Overview then shows "Complete the settings: Leave loading" and never crashes. Test: Task 2 `test_missing_settings_requires_leave_loading`, and the Task 3 smoke test.
3. **A typo in a scenario's step,** or a year before the scale starts. The page shows "Scenarios: …" as a danger callout and stays usable. Tests: Task 2 `test_unknown_step_raises_with_scenario_name`, Task 3 `test_unknown_scenario_step_shows_callout`.
4. **A blank year or step cell in the scenarios grid.** It is stored as NULL, not as "" or NaN. Test: Task 3 `clean_rows` coverage in the smoke test, by seeding through `save_rows` with None.
5. **No scale imported.** The salary-step dropdown offers only "—" and the manual gross still works. Test: Task 3 `test_runs_on_populated_db_without_scale`.

---

### Task 1: Store, migration 2

**Files:** Modify `apps/planner/store.py`, `apps/planner/tests/test_store.py`, `apps/planner/budget.py` (only the two new `Settings` fields).

**Interfaces:**
- **Produces `MIGRATIONS[1]`,** exactly:

```sql
CREATE TABLE salary_levels (id INTEGER PRIMARY KEY, step TEXT NOT NULL,
  effective_from TEXT NOT NULL CHECK (effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  annual REAL NOT NULL CHECK (annual > 0), UNIQUE (step, effective_from));
ALTER TABLE settings ADD COLUMN salary_step TEXT;
ALTER TABLE settings ADD COLUMN include_leave_loading INTEGER;
ALTER TABLE scenarios ADD COLUMN year INTEGER CHECK (year IS NULL OR year BETWEEN 2000 AND 2100);
ALTER TABLE scenarios ADD COLUMN salary_step TEXT;
```

- **Changes to `TABLES`:**
  - `"scenarios"` becomes `["name", "sacrifice_per_pay", "after_tax_per_pay", "year", "salary_step"]`.
  - New entry `"salary_levels": ["step", "effective_from", "annual"]`.
- **`load_settings`** returns `bool` for both `include_medicare_levy` and `include_leave_loading`. Define the set of boolean settings once.
- **Depends on Task 2:** `budget.Settings` gains `salary_step: Optional[str] = None` and `include_leave_loading: Optional[bool] = None`, appended at the end. Task 1 adds these two fields to `Settings` itself, so that `load_settings` works; Task 2 builds on them.

- [ ] **Step 1: Write the failing tests:**
  - `test_migration_2_keeps_v1_data`: build a v1 DB by running `MIGRATIONS[0]`, setting `user_version` to 1 and inserting one row per table. Then `connect`, and check that `user_version == 2`, the rows are intact, and the new columns are None.
  - `test_salary_levels_reject_duplicates_and_bad_values`: a duplicate (step, effective_from), `annual <= 0` and a non-ISO date each raise `sqlite3.IntegrityError`.
  - `test_scenario_year_range`: year 1999 is rejected; year None is accepted.
  - `test_leave_loading_setting_round_trips_as_bool`.
  - `test_save_rows_inserts_salary_levels`.
- [ ] **Step 2: Run the tests and confirm they fail (RED).**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite and confirm it passes (GREEN).** Existing tests must still pass. `test_fresh_db_has_only_neutral_settings` still expects `Settings(pays_per_year=26)`.
- [ ] **Step 5: Commit** as `planner: add the pay scale table and scenario year`.

---

### Task 2: Budget, salary rules

**Files:** Modify `apps/planner/budget.py`, `apps/planner/tax.py` (add `TAX_YEAR = "2026-27"`), `apps/planner/tests/test_budget.py`.

**Interfaces (the names Task 3 uses):**
- **Constants:** `LEAVE_LOADING_RATE = 0.175`, `LEAVE_LOADING_WEEKS = 4`.
- **`def leave_loading(annual: float) -> float`.**
- **`def reference_date(year: Optional[int], today: date) -> date`.**
- **`def salary_on(rates: Sequence[Mapping], step: str, on: date) -> float`.** Each rate row has `step`, `effective_from` (ISO string) and `annual`. Raises `ValueError(f"no salary for step {step} on {on.isoformat()}")`.
- **`def salary_steps(rates: Sequence[Mapping]) -> list[str]`.** Returns the unique steps, sorted numerically per dot-separated part where the parts are numeric (e.g. `A.2` comes before `A.10`).
- **`missing_settings`:**
  - `include_leave_loading` is always required.
  - `yearly_gross` is listed as missing only when **both** `yearly_gross` and `salary_step` are None.
  - Everything else is unchanged.
- **`ScenarioResult`** gains these fields, appended: `year: Optional[int]`, `salary_step: Optional[str]`, `salary: float`, `leave_loading: float`, `gross: float`.
- **`def scenario_results(scenarios, s, total_week, salary_rates: Sequence[Mapping] = (), today: Optional[date] = None)`.** `today` defaults to `date.today()`. A ValueError from `salary_on` is re-raised as `ValueError(f"scenario {name}: {message}")`.

- [ ] **Step 1: Write the failing tests.** All amounts are synthetic, with `SCALE = [{"step": "A.1", "effective_from": "2026-03-01", "annual": 100_000}, {"step": "A.1", "effective_from": "2027-03-01", "annual": 103_500}, {"step": "A.2", "effective_from": "2026-03-01", "annual": 110_000}]`.
  - `test_salary_on_picks_latest_effective_rate`:
    - `salary_on(SCALE, "A.1", date(2026, 11, 19)) == 100_000`;
    - `salary_on(SCALE, "A.1", date(2027, 3, 1)) == 103_500`;
    - `date(2026, 2, 28)` raises ValueError;
    - step `"B.1"` raises ValueError.
  - `test_reference_date`: `reference_date(2027, d) == date(2027, 3, 1)` and `reference_date(None, d) == d`.
  - `test_leave_loading`: `leave_loading(52_000) == pytest.approx(700)`.
  - `test_salary_steps_sorted_naturally`: `salary_steps([{"step": s, ...} for s in ["A.10", "A.2", "A.2"]]) == ["A.2", "A.10"]`.
  - `test_missing_settings_requires_leave_loading`, plus `test_salary_step_replaces_yearly_gross_requirement`.
  - `test_scenario_uses_settings_step_today_with_loading`. Use Settings with `salary_step="A.1"`, `include_leave_loading=True` and `super_rate=0.12`, with today = `date(2026, 11, 19)`. Then:
    - salary 100_000;
    - loading `100_000/52*4*0.175`;
    - gross = salary + loading;
    - taxable = gross − sacrifice;
    - `employer_super == 12_000`.
  - `test_scenario_year_uses_march_rate`: year 2027 gives a salary of 103_500.
  - `test_scenario_own_step_overrides_settings`: step A.2 gives 110_000.
  - `test_manual_gross_without_step`: salary == yearly_gross, and a year has no effect.
  - `test_unknown_step_raises_with_scenario_name`.
  - **Existing fixtures** need `include_leave_loading=False` added. With `False`, the expected values of every existing scenario test stay unchanged.
- [ ] **Step 2: Run the tests and confirm they fail (RED).**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite and confirm it passes (GREEN).**
- [ ] **Step 5: Commit** as `planner: derive salary from the pay scale, add leave loading`.

---

### Task 3: UI

**Files:** Modify `apps/planner/planner.py`, `apps/planner/tests/test_notebook.py`.

**Interfaces:**
- **Consumes:** everything from Tasks 1 and 2.
- **`LABELS`:**
  - `yearly_gross` becomes "Yearly gross or salary step";
  - add `salary_step` as "Salary step";
  - add `include_leave_loading` as "Leave loading".
- **Settings tab:**
  - A "Salary step" dropdown with "—" (None) plus `budget.salary_steps(scale)`.
  - A "Leave loading" dropdown with —/Yes/No, the same pattern as Medicare.
  - The yearly-gross input is labelled "Yearly gross (without salary step)".
  - A read-only table "Pay scale (imported)" showing step, from and annual, or the line "No pay scale imported" when it's empty.
- **Scenarios grid (Settings tab):** gains `year` (nullable Int64) and `salary_step` (String) columns. `clean_rows` turns a blank, NaN or empty value into None for both.
- **Overview:**
  - The scenario table gains "Year" ("—" when None), "Step" ("—" when None) and "Gross / year".
  - A line reads "Tax rates {tax.TAX_YEAR}".
  - When `scenario_results` raises ValueError, show `mo.callout(f"Scenarios: {message}", kind="danger")` instead of the results.
- **Tax details:** gains Salary, Leave loading and Gross columns. It handles a ValueError from `scenario_results` the same way.
- **The pay scale** is loaded once per session with `store.load(conn, "salary_levels")` and passed as `salary_rates`. Pass `today=date.today()` explicitly.

- [ ] **Step 1: Write the failing smoke tests,** each running the notebook as a script per tab with `PLANNER_START_TAB`:
  - `test_runs_with_pay_scale`: synthetic scale, Settings step `A.1`, leave loading on, one scenario with year 2027 and one with step `A.2`. All tabs exit 0.
  - `test_unknown_scenario_step_shows_callout`: a scenario with step `Z.9`. Overview exits 0, and stdout or the HTML output contains "Scenarios:" if your existing smoke harness can see it. Otherwise assert exit 0 and no "Traceback" on stderr.
  - `test_runs_on_populated_db_without_scale`: manual gross, no scale. All tabs exit 0.
- [ ] **Step 2: Run them and confirm they fail (RED)** where they can. Exit-0 tests may already pass before the UI changes; then make sure at least one assertion depends on the new code.
- [ ] **Step 3: Implement, then check by hand in the browser pane:**
  - Run `marimo run planner.py --headless --host 127.0.0.1 --port 2719` with a temp `PLANNER_DB` holding a synthetic scale.
  - Pick a step and switch leave loading on; Gross / year should change.
  - Set one scenario's year to 2027 and another's step; their gross should differ as expected.
  - Enter a typo step; the danger callout should appear.
  - Stop the server and delete the temp DB afterwards.
- [ ] **Step 4: Run the full suite and confirm it passes (GREEN).**
- [ ] **Step 5: Commit** as `planner: choose salary step, year and leave loading in the UI`.

---

### After the tasks (controller, with the user)

- **Local import script.** Outside git: add `--salary-levels <csv>`, `--salary-step`, `--leave-loading yes|no`, and make `--yearly-gross` optional. The CSV with the real scale lives in the user's local folder.
- **Final whole-branch review,** then cherry-pick onto `main` and push.
- **Deploy and import.**
