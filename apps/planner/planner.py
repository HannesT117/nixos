# /// script
# requires-python = ">=3.12"
# dependencies = ["marimo==0.25.2", "polars"]
# ///

import marimo

__generated_with = "0.25.2"
app = marimo.App(width="medium", app_title="Budget planner")


@app.cell
def _():
    import sys

    import marimo as mo
    import polars as pl

    sys.path.insert(0, str(mo.notebook_dir()))

    import budget
    import store

    return budget, mo, pl, store


@app.cell
def _(store):
    conn = store.open_from_env()
    return (conn,)


@app.cell
def _(budget):
    TABS = ["Overview", "Expenses", "Trips", "Settings", "Tax details"]

    LABELS = {
        "yearly_gross": "Yearly gross",
        "pays_per_year": "Pays per year",
        "super_rate": "Employer super rate",
        "include_medicare_levy": "Medicare levy",
        "mls": "Medicare levy surcharge",
        "partner_income": "Partner income",
        "children": "Children",
        "savings_target_week": "Savings target / week",
        "weeks_per_trip": "Weeks per trip",
        "baseline_scenario_id": "Baseline scenario",
    }

    def money(value):
        sign = "-" if value < 0 else ""
        return f"{sign}${abs(value):,.2f}"

    def money_or_dash(value):
        return "—" if value is None else money(value)

    def is_blank(value):
        return value is None or value == "" or value != value

    def clean_rows(rows, defaults):
        cleaned = []
        for row in rows:
            out = {"id": None if is_blank(row.get("id")) else int(row["id"])}
            for column, default in defaults.items():
                value = row.get(column)
                out[column] = default if is_blank(value) else value
            cleaned.append(out)
        return cleaned

    def weeks_per_trip_ok(settings):
        return settings.weeks_per_trip is not None and settings.weeks_per_trip > 0

    def incomplete_message(settings):
        names = [LABELS[name] for name in budget.missing_settings(settings)]
        return f"Complete the settings: {', '.join(names)}"

    return (
        LABELS,
        TABS,
        clean_rows,
        incomplete_message,
        money,
        money_or_dash,
        weeks_per_trip_ok,
    )


@app.cell
def _(conn, mo, store):
    get_scenarios, set_scenarios = mo.state(
        store.load(conn, "scenarios"), allow_self_loops=True
    )
    get_expenses, set_expenses = mo.state(
        store.load(conn, "expenses"), allow_self_loops=True
    )
    get_trips, set_trips = mo.state(store.load(conn, "trips"), allow_self_loops=True)
    get_settings, set_settings = mo.state(store.load_settings(conn))
    get_expense_rows_revision, set_expense_rows_revision = mo.state(
        0, allow_self_loops=True
    )
    get_tab, set_tab = mo.state("Overview")
    get_error, set_error = mo.state(None)
    return (
        get_error,
        set_error,
        get_expense_rows_revision,
        get_expenses,
        get_scenarios,
        get_settings,
        get_tab,
        get_trips,
        set_expense_rows_revision,
        set_expenses,
        set_scenarios,
        set_settings,
        set_tab,
        set_trips,
    )


@app.cell
def _(set_error):
    def guard(table, action):
        def run(*args):
            try:
                result = action(*args)
            except Exception as error:
                set_error(f"{table}: {type(error).__name__}: {error}")
                return None
            set_error(None)
            return result

        return run

    return (guard,)


@app.cell
def _(get_error, mo):
    mo.callout(
        f"Save failed, change not stored. {get_error()}", kind="danger"
    ) if get_error() else None
    return


@app.cell
def _(TABS, mo, set_tab):
    mo.ui.tabs({name: mo.md("") for name in TABS}, on_change=set_tab)
    return


@app.cell
def _(
    budget,
    get_expenses,
    get_scenarios,
    get_settings,
    get_tab,
    get_trips,
    incomplete_message,
    mo,
    money,
    money_or_dash,
):
    mo.stop(get_tab() != "Overview")
    _settings = get_settings()
    mo.stop(
        bool(budget.missing_settings(_settings)),
        mo.md(f"**{incomplete_message(_settings)}**"),
    )
    _trips = budget.trip_summary(get_trips(), _settings.weeks_per_trip)
    _totals = budget.expense_totals(get_expenses(), _trips.trips_week)
    _results = budget.scenario_results(get_scenarios(), _settings, _totals.total_week)
    _cards = mo.hstack(
        [
            mo.stat(label="Recurring / week", value=money(_totals.recurring_week)),
            mo.stat(label="Trips / week", value=money(_totals.trips_week)),
            mo.stat(label="Total / week", value=money(_totals.total_week)),
            mo.stat(label="Done trips", value=str(_trips.done_trips)),
            mo.stat(label="Average trip", value=money(_trips.average_trip)),
        ],
        justify="start",
        wrap=True,
    )
    _table = mo.ui.table(
        [
            {
                "Scenario": r.name,
                "Net / week": money(r.net_week),
                "Rest / week": money(r.rest_week),
                "Cash savings / week": money(r.cash_savings_week),
                "Super gain / week": money(r.super_gain_week),
                "Take-home reduction / week": money_or_dash(r.takehome_reduction_week),
            }
            for r in _results
        ],
        selection=None,
        pagination=False,
    )
    _scenario_cards = mo.vstack(
        [
            mo.vstack(
                [
                    mo.md(f"**{r.name}**"),
                    mo.hstack(
                        [
                            mo.stat(label="Net / week", value=money(r.net_week)),
                            mo.stat(label="Rest / week", value=money(r.rest_week)),
                            mo.stat(
                                label="Cash savings / week",
                                value=money(r.cash_savings_week),
                            ),
                            mo.stat(
                                label="Super gain / week",
                                value=money(r.super_gain_week),
                            ),
                        ],
                        justify="start",
                        wrap=True,
                    ),
                ]
            )
            for r in _results
        ]
    )
    mo.vstack([_cards, mo.md("### Scenarios"), _table, _scenario_cards])
    return


@app.cell
def _(
    budget,
    clean_rows,
    conn,
    get_expense_rows_revision,
    get_expenses,
    get_tab,
    guard,
    mo,
    set_expense_rows_revision,
    set_expenses,
    store,
):
    mo.stop(get_tab() != "Expenses")
    get_expense_rows_revision()

    def _build():
        seed = store.load(conn, "expenses")
        defaults = {"name": "", "amount": 0, "period": "Monthly"}

        def current():
            return clean_rows(
                [
                    {
                        "id": line["id"],
                        "name": line["name"].value,
                        "amount": line["amount"].value,
                        "period": line["period"].value,
                    }
                    for line in lines
                ],
                defaults,
            )

        def persist(rows):
            set_expenses(store.save_rows(conn, "expenses", get_expenses(), rows))

        def on_edit(_):
            persist(current())

        def delete(index):
            rows = current()
            del rows[index]
            persist(rows)
            set_expense_rows_revision(lambda n: n + 1)

        def add(_):
            persist([*current(), {"id": None, **defaults}])
            set_expense_rows_revision(lambda n: n + 1)

        on_edit = guard("expenses", on_edit)
        delete = guard("expenses", delete)
        add = guard("expenses", add)

        lines = [
            {
                "id": row["id"],
                "name": mo.ui.text(
                    value=row["name"], placeholder="Name", on_change=on_edit
                ),
                "amount": mo.ui.number(
                    value=row["amount"], step=0.01, on_change=on_edit
                ),
                "period": mo.ui.dropdown(
                    list(budget.PERIODS), value=row["period"], on_change=on_edit
                ),
            }
            for row in seed
        ]
        deletes = mo.ui.array(
            [
                mo.ui.button(label="Delete", on_click=lambda _, i=i: delete(i))
                for i in range(len(lines))
            ]
        )
        adder = mo.ui.button(label="Add expense", on_click=add)
        rows_view = [
            mo.hstack(
                [line["name"], line["amount"], line["period"], button],
                justify="start",
                align="center",
                wrap=True,
            )
            for line, button in zip(lines, deletes.elements)
        ]
        return mo.vstack([*rows_view, adder]), adder, deletes

    expenses_view, add_expense_button, delete_expense_buttons = _build()
    expenses_view
    return add_expense_button, delete_expense_buttons


@app.cell
def _(
    budget,
    clean_rows,
    conn,
    get_settings,
    get_tab,
    get_trips,
    guard,
    mo,
    money,
    pl,
    set_trips,
    store,
    weeks_per_trip_ok,
):
    mo.stop(get_tab() != "Trips")
    _settings = get_settings()
    _columns = store.TABLES["trips"]
    _defaults = {column: None for column in _columns}
    _schema = {
        "id": pl.Int64,
        **{
            column: pl.Float64 if column.endswith("_price") else pl.Utf8
            for column in _columns
        },
    }

    def _on_change(rows, defaults=_defaults):
        set_trips(
            store.save_rows(
                conn, "trips", get_trips(), clean_rows(rows.to_dicts(), defaults)
            )
        )

    trips_editor = mo.ui.data_editor(
        pl.DataFrame(get_trips(), schema=_schema),
        editable_columns=_columns,
        on_change=guard("trips", _on_change),
        label="Trips (a trip counts once its fuel price is set, 0 included)",
    )
    if weeks_per_trip_ok(_settings):
        _summary = budget.trip_summary(get_trips(), _settings.weeks_per_trip)
        _cards = mo.hstack(
            [
                mo.stat(label="Done trips", value=str(_summary.done_trips)),
                mo.stat(label="Average trip", value=money(_summary.average_trip)),
                mo.stat(label="Trips / week", value=money(_summary.trips_week)),
            ],
            justify="start",
            wrap=True,
        )
    else:
        _cards = mo.md("**Set weeks per trip**")
    mo.vstack([_cards, trips_editor])
    return (trips_editor,)


@app.cell
def _(LABELS, conn, get_scenarios, get_tab, guard, mo, set_settings, store):
    mo.stop(get_tab() != "Settings")
    _settings = store.load_settings(conn)

    def _save(field, convert=lambda v: v):
        def handler(value):
            store.set_setting(conn, field, convert(value))
            set_settings(store.load_settings(conn))

        return guard("settings", handler)

    def _number(field, convert=None, **kwargs):
        return mo.ui.number(
            value=getattr(_settings, field),
            label=LABELS[field],
            on_change=_save(
                field, lambda v: None if v is None else (convert or float)(v)
            ),
            **kwargs,
        )

    def _non_negative_int(value):
        return max(0, int(value))

    def _positive(value):
        return float(value) if value and value > 0 else None

    _medicare_options = {"—": None, "Yes": True, "No": False}
    _medicare_name = next(
        name
        for name, flag in _medicare_options.items()
        if flag is _settings.include_medicare_levy
    )
    _baseline_options = {
        (s["name"] or f"Scenario {s['id']}"): s["id"] for s in get_scenarios()
    }
    _baseline_name = next(
        (
            name
            for name, scenario_id in _baseline_options.items()
            if scenario_id == _settings.baseline_scenario_id
        ),
        None,
    )
    settings_controls = [
        _number("yearly_gross", step=100),
        _number("pays_per_year", int, step=1),
        _number("super_rate", step=0.005),
        mo.ui.dropdown(
            _medicare_options,
            value=_medicare_name,
            label=LABELS["include_medicare_levy"],
            on_change=_save("include_medicare_levy"),
        ),
        mo.ui.dropdown(
            ["none", "single", "family"],
            value=_settings.mls,
            label=LABELS["mls"],
            allow_select_none=True,
            on_change=_save("mls"),
        ),
        _number("partner_income", step=100),
        _number("children", _non_negative_int, step=1),
        _number("savings_target_week", step=10),
        mo.ui.number(
            value=_settings.weeks_per_trip,
            label=LABELS["weeks_per_trip"],
            step=0.5,
            on_change=_save("weeks_per_trip", _positive),
        ),
        mo.ui.dropdown(
            _baseline_options,
            value=_baseline_name,
            label=LABELS["baseline_scenario_id"],
            allow_select_none=True,
            on_change=_save("baseline_scenario_id"),
        ),
    ]
    mo.vstack(settings_controls)
    return (settings_controls,)


@app.cell
def _(
    clean_rows,
    conn,
    get_scenarios,
    get_tab,
    guard,
    mo,
    pl,
    set_scenarios,
    set_settings,
    store,
):
    mo.stop(get_tab() != "Settings")
    _defaults = {"name": "", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}
    _schema = {
        "id": pl.Int64,
        "name": pl.Utf8,
        "sacrifice_per_pay": pl.Float64,
        "after_tax_per_pay": pl.Float64,
    }

    def _on_change(rows, defaults=_defaults):
        set_scenarios(
            store.save_rows(
                conn, "scenarios", get_scenarios(), clean_rows(rows.to_dicts(), defaults)
            )
        )
        set_settings(store.load_settings(conn))

    scenarios_editor = mo.ui.data_editor(
        pl.DataFrame(get_scenarios(), schema=_schema),
        editable_columns=list(_defaults),
        on_change=guard("scenarios", _on_change),
        label="Scenarios (amounts per pay)",
    )
    scenarios_editor
    return (scenarios_editor,)


@app.cell
def _(
    budget,
    get_expenses,
    get_scenarios,
    get_settings,
    get_tab,
    get_trips,
    incomplete_message,
    mo,
    money,
    money_or_dash,
):
    mo.stop(get_tab() != "Tax details")
    _settings = get_settings()
    mo.stop(
        bool(budget.missing_settings(_settings)),
        mo.md(f"**{incomplete_message(_settings)}**"),
    )
    _trips = budget.trip_summary(get_trips(), _settings.weeks_per_trip)
    _totals = budget.expense_totals(get_expenses(), _trips.trips_week)
    _results = budget.scenario_results(get_scenarios(), _settings, _totals.total_week)
    mo.ui.table(
        [
            {
                "Scenario": r.name,
                "Sacrifice / year": money(r.sacrifice_year),
                "After-tax contribution / year": money(r.after_tax_year),
                "Taxable income": money(r.taxable),
                "Gross tax": money(r.gross_tax),
                "LITO": money(r.lito),
                "Medicare levy": money(r.medicare),
                "MLS rate": f"{r.mls_rate:.2%}",
                "MLS": money(r.mls),
                "Total tax": money(r.total_tax),
                "Net / year": money(r.net_year),
                "Take-home reduction / week": money_or_dash(
                    r.takehome_reduction_week
                ),
                "Super gain / year": money(r.super_gain_year),
                "Employer super": money(r.employer_super),
                "Concessional total": money(r.concessional_total),
                "Cap left": money(r.cap_left),
                "FHSS release": money(r.fhss_release),
            }
            for r in _results
        ],
        selection=None,
        pagination=False,
    )
    return


if __name__ == "__main__":
    app.run()
