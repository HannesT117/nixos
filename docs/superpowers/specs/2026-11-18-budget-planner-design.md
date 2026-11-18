# Budget planner (marimo) — design

## Intent

A personal budget planner on gmktec. It replaces the Grist service at money.jrdn.cx outright: Grist
is removed in the same change, with no parallel run. It also replaces a local salary-sacrifice script
and a local spreadsheet, neither of which is in git.

It is used occasionally, to plan: "what's left per week under each salary-sacrifice scenario, given
recurring expenses, trips and a savings target?" It may later grow into tracking actual spending
(bank/app exports) and investments.

Why it replaces Grist: Grist's UI felt poor, and changing the structure meant either clicking through
the GUI or rebuilding the whole document from a script. Here the structure is code: a change is an
edit, a commit and a `nixos-rebuild`, and the data survives it.

## Goals

- Per scenario: net per week, expenses per week, super gain per week, cash savings per week, rest
  per week. Plus tax details: taxable income, gross tax, LITO, Medicare levy, MLS, total tax,
  employer super, concessional total, cap left, FHSS release.
- The same tax results as the existing local salary-sacrifice script, for every combination of tax
  settings.
- Recurring expenses with a period chosen from a dropdown: Weekly, Fortnightly, Monthly, Quarterly,
  Yearly.
- Trips kept separate from expenses. A trip counts as done once it has a fuel price. The average done
  trip, divided by weeks per trip, gives "Trips / week".
- Total per week = recurring per week + trips per week. Super gain counts toward the savings target.
- Usable on a phone: cards wrap, and editing works without a mouse.
- Structure changes keep existing data, through automatic migrations at startup.

## Non-goals (for now)

- Tracking actual spending or investments. When that comes, it goes into beancount (with importers),
  and the planner reads the ledger through beancount's Python API. It does not get its own
  transaction tables. That is a separate design.
- More than one user, sharing, or roles.
- An HTTP API.
- A migration path from Grist. The planner is a hobby project barely in use, so Grist and its data
  are simply removed.

## Anti-goals (failure even if it works)

- Personal data anywhere in git. That covers real amounts, names of people or expenses, tax
  circumstances, the local spreadsheet or its contents, and paths to local private files. It applies
  to code, tests, fixtures, seeds, migrations, docs and commit messages. Tests use synthetic values.
  Code reads names and amounts from the database, never from literals.
- Silent data loss: a stale browser tab, or a schema change, deleting or reverting rows.
- The app reachable without Authelia, including by local processes on the server.
- Totals that silently drop a line, for example an unknown period turning into $0.

## Constraints

- NixOS flake on gmktec, with impermanence, Lanzaboote and static users (no DynamicUser; see
  CLAUDE.md). Secrets live in `/persist/secrets`.
- Caddy terminates TLS, with Porkbun DNS-01. Authelia forward-auth requires password + passkey.
  The firewall is nftables, and web services are only reachable through Caddy.
- Pinned nixpkgs `1a08097f` ships `python3Packages.marimo` 0.25.1 and `polars` 1.42.1. Checked with
  `nix eval`. 0.25.1 is past the CVE-2026-39987 fix in 0.23.0.
- marimo's `data_editor` has no dropdown or select cells. Checked in the 0.17.6 and 0.25.2 source.
  So any column that needs a fixed set of values is edited through a form list (`mo.ui.array` of
  `mo.ui.dictionary` with `mo.ui.dropdown`), not the grid.
- marimo gives each browser tab its own kernel session. Tabs don't see each other's edits until reload.
- No code comments unless approved (personal rules).

## Approaches considered

| | Approach | Trade-off | Outcome |
|---|---|---|---|
| A | Keep Grist + a script that syncs schema changes into the live document | Smallest step. But the UI the user called poor stays | Rejected |
| **B** | **marimo app: one Python notebook served with `marimo run`, SQLite on the server** | Structure is code; tax logic reused, not ported to formulas; live recalculation; works on a phone. You own the editing UI and the migrations | **Chosen** |
| C | beancount + Fava | Best for actual spending and investments; can't do forward-looking scenario planning | Later complement to B, not a replacement |

Also dismissed:
- **Firefly III / Actual Budget:** fixed structure, no scenario modelling.
- **NocoDB / Baserow:** same GUI-defined structure problem as Grist.
- **Datasette / Evidence:** read-only.
- **Streamlit:** roughly equal to marimo; marimo's per-cell reactivity and the spike results won.

The choice was pressure-tested by an independent review and a local throwaway spike with synthetic
data.

What the spike showed:
- Edits persist to SQLite.
- It works behind a plain Caddy proxy (websocket included).
- Cards wrap on mobile.
- The form-list dropdown saves correctly.

Bugs it exposed, which this design fixes:
- Whole-table saves from stale state.
- A closure over an old row list.
- Missing Medicare/MLS settings and employer super.

## Design

### Where the code lives

`apps/planner/` in this repo, deployed by the flake. This is my call: one repo, one deploy, and the
code contains no data.

```
apps/planner/
  planner.py      marimo notebook: UI only, calls the modules below
  tax.py          rates table + bracket/LITO/MLS/tax functions, written fresh (see below)
  budget.py       pure functions: per-week conversion, trip summary, expense totals, scenario results
  store.py        SQLite access: migrations, load, per-row save
  tests/          pytest, synthetic values only
nix/services/planner.nix
```

Core logic is pure: `tax.py` and `budget.py` take plain data and return plain data, and only
`store.py` touches the database. `planner.py` wires widgets to those modules and holds no business
rules.

`tax.py` is written fresh. It takes the statutory rates and the calculation logic from the local
script, but **nothing else**. The script's docstring examples and CLI help contain real personal
figures, so no text, example or default is copied from it.

### Data model (SQLite)

Every table has `id INTEGER PRIMARY KEY`. The migrations create empty tables and seed only a single
`settings` row.
- Every column that describes a personal circumstance starts as **NULL**: Medicare levy, MLS,
  partner income, children, gross, super rate, savings target and weeks per trip. A default such as
  "levy off" would itself encode a circumstance.
- Until those are set, the Overview shows "Complete the settings" instead of results.
- Only `pays_per_year` gets a default (26).

- `settings`: a single row with typed columns:
  - `yearly_gross`, `pays_per_year`, `super_rate`
  - `include_medicare_levy` (bool), `mls` ('none' | 'single' | 'family'), `partner_income`,
    `children`
  - `savings_target_week`, `weeks_per_trip`
  - `baseline_scenario_id`
- `scenarios`: `name`, `sacrifice_per_pay`, `after_tax_per_pay`.
- `expenses`: `name`, `amount`, `period`, with a CHECK that `period` is one of the five values.
- `trips`: `dates`, `transport`, `transport_price`, `insurance`, `insurance_price`, `fuel`,
  `fuel_price`, `accommodation`, `accommodation_price`.

**Migrations:**
- `store.py` holds an ordered list of SQL migrations and applies the missing ones at startup,
  tracked with `PRAGMA user_version`, each in a transaction.
- Adding or renaming a column is a new entry in the list. Existing entries are never edited.

**Saving by row:**
- Each editor remembers the ids it loaded. On change, it diffs against that snapshot:
  - changed rows → `UPDATE … WHERE id = ?`;
  - rows without an id → `INSERT`;
  - loaded ids that are now missing → `DELETE`.
- Invariant: **a save never deletes or changes a row the editor did not load.** A stale tab can
  therefore only overwrite rows it edited itself (last write wins per row). It can never wipe rows
  added elsewhere.
- After an `INSERT`, the snapshot takes the new id. Otherwise the next change would insert the row
  again.
- `settings` is updated **per column**: only the field that changed is written. A stale tab can't
  revert other settings.

### Calculations (`budget.py`)

- Per week:
  - Weekly × 1
  - Fortnightly ÷ 2
  - Monthly × 12/52
  - Quarterly × 4/52
  - Yearly ÷ 52

  An unknown period is an error, not $0. The DB CHECK and the dropdown make it unreachable.
- Trips:
  - done = a fuel price has been entered. 0 counts, so a trip without fuel (e.g. a flight) can be
    marked done by entering 0. Empty means not done.
  - average trip = mean total of done trips (0 if none)
  - trips / week = average ÷ weeks per trip (weeks per trip must be > 0, enforced in settings input
    and the DB)
- Scenario:
  - taxable, tax components and net per year are computed exactly as the local script does, with
    Medicare and MLS driven by settings;
  - net / week = net per year ÷ 52;
  - super gain / week = (sacrifice × (1 − contributions tax) + after-tax contributions) ÷ 52;
  - cash savings / week = max(0, savings target − super gain / week);
  - rest / week = net / week − total expenses / week − cash savings / week;
  - takehome reduction is measured against the baseline scenario.
- Employer super = gross × super rate. Concessional total = employer super + sacrifice. Cap left and
  FHSS release as in the local script.

### UI (`planner.py`)

Tabs:
- **Overview**:
  - scenario results table (name, net, expenses, cash savings, super gain, rest, all per week);
  - cards: Recurring / week, Trips / week, Total / week;
  - trip cards: done trips, average trip, weeks per trip, trips / week;
  - savings target.

  On narrow screens, scenario results show as one card per scenario instead of a wide table.
- **Expenses**: a form list. Each row has a name, an amount, a period dropdown, its per-week amount
  and a Delete button, with "Add expense" below.
- **Trips**: the grid editor (the `id` column is not editable), with the trip cards above it.
- **Settings**: number inputs, the Medicare levy toggle, an MLS dropdown, and the scenarios grid.
  Baseline is chosen with a dropdown of scenario names.
- **Tax details**: all scenario columns.

Amounts are shown as AUD with two decimals.

### Deployment (`nix/services/planner.nix`)

- A static `planner` user and group. State lives in `/var/lib/planner`. The impermanence entry
  carries `user`, `group` and `mode = "0700"`, like the `rex` entry.
- `InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/planner"`, as `rex` and
  `ollama` do.
- A systemd service runs
  `marimo run <store path>/planner.py --headless --host 127.0.0.1 --port 2719` with
  `python3.withPackages (ps: [ ps.marimo ps.polars ])` and `PLANNER_DB=/var/lib/planner/planner.sqlite`.
- `HOME` points at the state directory, in case marimo writes config or cache. The builder verifies
  what it writes.
- Hardening is in line with the other services.
- The app **refuses to start** if `PLANNER_DB` is unset. There is no default path next to the code.
- Port isolation: an nftables `output` rule, so that on `lo` only the `caddy` user may open
  connections to 2719. The pattern moves over from `grist.nix`, including the `preCheckRuleset`
  substitution.
- Caddy: the money.jrdn.cx vhost becomes plain `forward_auth` to Authelia + `reverse_proxy
  localhost:2719`.
  - `reverse-proxy.nix` currently binds `grist = config.services.grist.environment` and builds the
    header names, port and logout path from it. That binding is deleted and the headers are written
    literally. Otherwise evaluation fails once Grist is gone.
  - The Bearer-token bypass must go entirely. The app has no login of its own, so a leftover bypass
    would expose it without auth.
- Authelia: the existing `two_factor` rule for money.jrdn.cx stays as it is.
- Grist is removed in the same change:
  - `nix/services/grist.nix` and its import;
  - the Grist-specific Caddy parts;
  - the `/var/lib/grist-core` impermanence entry;
  - the README row.

  After the switch, the user deletes `/persist/var/lib/grist-core` and `/persist/secrets/grist-env`
  on the server.
- Backup: a daily systemd timer runs `sqlite3 planner.sqlite ".backup …"` into
  `/var/lib/syncthing/planner-backup/<timestamp>.sqlite`, keeps the last 30, and chowns them to
  syncthing. The backup unit runs as root, like the paperless backup.
  - Backups leave the server through Syncthing (the user's decision).
  - Syncthing folders aren't declared in Nix in this repo. After the first deploy, the user adds
    `/var/lib/syncthing/planner-backup` as a folder in the Syncthing web UI and shares it with their
    device. The plan includes this manual step.

### Importing the existing data (one-off, outside git)

A one-off import script lives in the user's local, untracked working folder, next to the spreadsheet.
It is never committed, and it is deleted after use.

- It reads the local spreadsheet and writes a fresh SQLite file through `store.py`.
- Every name and amount comes from the spreadsheet at runtime. Personal values come from command-line
  arguments. The script contains no personal literals.
- Before it is written, the user describes how the spreadsheet maps onto the four tables, in the
  session that runs the import. That mapping is not recorded in git. Known points to settle there:
  - Amounts the old sheet added on top of the trip average are ordinary expenses (the user's
    decision). Their period is chosen at import.
  - A trip marked done in the sheet but without a fuel price gets fuel 0, so it still counts as
    done.

The file is copied to the server with `scp`, installed as `planner:planner` 0600 at the `PLANNER_DB`
path, and the local copy is deleted.

After the import is checked, the user deletes the local salary-sacrifice script, the local Grist
scripts, the spike, and the migrated spreadsheet tables. The planner's own `tax.py` then holds the
tax rules.

### Testing

All test values are synthetic.

- `tax.py`: a table of synthetic cases covering every bracket, LITO band, Medicare on/off, MLS
  single and family (with partner income and children), and tier edges. Expected values are produced
  once by the local script before it is deleted, and frozen in the test.
- `budget.py`:
  - every period conversion;
  - trips with and without done trips;
  - weeks per trip validation;
  - scenario parity with the tax module;
  - total = recurring + trips.
- `store.py`, against a temp DB:
  - migrations from an empty DB and from each earlier version;
  - per-row save;
  - the stale-tab invariant. Two editors load, one adds a row, the other saves: the added row
    survives.
- Smoke: run the notebook as a script with a temp `PLANNER_DB`, and expect exit 0.
- **Leak guard:** one hook script, installed in this repo and in the dotfiles repo. The dotfiles
  repo matters because `~/.claude/rules`, `agents`, `skills` and `hooks` are symlinked into it, so
  notes written during a finance session would be pushed.
  - The script itself holds no private data, so it can live in dotfiles. It runs as three hooks:
    - `pre-commit` checks the staged diff;
    - `commit-msg` checks the message;
    - `pre-push` checks every commit in `@{push}..HEAD`, diffs and messages. This catches rebases,
      cherry-picks and `--no-verify` commits.
  - It matches against a deny-list kept outside every repo. The user maintains the list: names,
    amounts, employer, the personal figures in the local script, and similar.
  - It **fails closed**. It blocks when the list is missing or empty, or when the list's resolved
    path lies inside a git work tree. Many `~/.config/*` folders are symlinks into dotfiles.
  - Numbers are normalised before matching: separators (`,` `_` space) removed, trailing `.0`/`.00`
    dropped. So 1,234.00, 1_234 and 1234 all match.
  - It rejects data files outright, whatever their content: `*.sqlite`, `*.db`, `*.numbers`,
    `*.csv`, `*.xlsx`. The same patterns go into `.gitignore`.
  - Known gaps, accepted:
    - GitHub web edits bypass it.
    - So do commits made in the server's `/etc/nixos` checkout. The rule is: never commit there,
      only pull.
  - The builder writes the hook and an empty list file, then tells the user to fill it in. It
    doesn't guess the terms. The empty list blocks commits until it's filled.
- Server checks after deploy:
  - unauthenticated `curl https://money.jrdn.cx` is redirected to Authelia, and so is the same
    request with `Authorization: Bearer x`;
  - a local `curl 127.0.0.1:2719` as a non-caddy user is rejected;
  - the app works after login, including on a phone;
  - the data survives a reboot;
  - a backup file has arrived on the device the Syncthing folder is shared with.

## Open questions

- **What happens when the Authelia session expires with a tab open?** The websocket was opened
  before expiry and may keep working until reload. This needs testing after deploy. If it keeps
  working indefinitely, decide whether that's acceptable for a single user on the tailnet.

## Left to the builder

- Exact widget layout, labels and styling within the tabs above.
- Test framework details, and how tests run locally (e.g. `uv run pytest` with a script header, or a
  flake `checks` entry).
- The marimo port, if 2719 clashes with anything.
