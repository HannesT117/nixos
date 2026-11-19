from dataclasses import replace
from datetime import date

import pytest

from budget import (
    LEAVE_LOADING_RATE,
    LEAVE_LOADING_WEEKS,
    PERIODS,
    ExpenseTotals,
    Settings,
    TripSummary,
    valid_weeks_per_trip,
    expense_totals,
    is_done,
    leave_loading,
    missing_settings,
    per_week,
    reference_date,
    salary_on,
    salary_steps,
    scenario_results,
    trip_summary,
    trip_total,
)
from tax import RATES, TAX_YEAR, TaxSettings, tax


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


@pytest.mark.parametrize("weeks", [0, None])
def test_trip_summary_rejects_non_positive_weeks(weeks):
    with pytest.raises(ValueError, match="weeks_per_trip must be positive"):
        trip_summary([{"transport_price": 100, "fuel_price": 0}], weeks)


@pytest.mark.parametrize("weeks,valid", [(None, False), (0, False), (-1, False), (0.5, True), (2, True)])
def test_valid_weeks_per_trip(weeks, valid):
    assert valid_weeks_per_trip(weeks) is valid


def test_trip_summary_without_done_trips_ignores_weeks():
    assert trip_summary([], None) == TripSummary(0, 0, 0)
    assert trip_summary([{"transport_price": 5, "fuel_price": None}], 0) == TripSummary(0, 0, 0)


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
                    mls="none", savings_target_week=200, weeks_per_trip=2, include_leave_loading=False)


def test_scenario_matches_tax_module_and_rules():
    [_, s100] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0},
                                     {"id": 2, "name": "b", "sacrifice_per_pay": 100, "after_tax_per_pay": 50}],
                                    SETTINGS, 500)
    expected_tax = tax(80_000 - 2600, 2600, TaxSettings(False, "none", 0, 0)).total
    assert s100.net_year == pytest.approx(80_000 - 2600 - expected_tax - 1300)
    assert s100.super_gain_week == pytest.approx((2600 * (1 - RATES["contributions_tax"]) + 1300) / 52)
    assert s100.cash_savings_week == pytest.approx(max(0, 200 - s100.super_gain_week))
    assert s100.rest_week == pytest.approx(s100.net_week - 500 - s100.cash_savings_week)
    assert s100.employer_super == 9600 and s100.concessional_total == 12_200
    assert s100.cap_left == 20_300
    assert s100.fhss_release == pytest.approx(2600 * (1 - RATES["contributions_tax"]) + 1300)


def test_reduction_is_per_scenario_without_contributions():
    zero = {"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}
    with_contrib = {"id": 2, "name": "b", "sacrifice_per_pay": 100, "after_tax_per_pay": 50}
    [r0, r] = scenario_results([zero, with_contrib], SETTINGS, 500)
    assert r0.takehome_reduction_week == 0
    assert r.takehome_reduction_week == pytest.approx((r0.net_year - r.net_year) / 52)
    assert r.takehome_reduction_week > 0


def test_empty_scenarios_with_complete_settings():
    assert scenario_results([], SETTINGS, 0) == []


def test_family_mls_requires_partner_income_and_children():
    with pytest.raises(ValueError, match="partner_income.*children"):
        scenario_results([], replace(SETTINGS, mls="family"), 0)


SCALE = [
    {"step": "A.1", "effective_from": "2026-03-01", "annual": 100_000},
    {"step": "A.1", "effective_from": "2027-03-01", "annual": 103_500},
    {"step": "A.2", "effective_from": "2026-03-01", "annual": 110_000},
]
TODAY = date(2026, 11, 19)
PLAIN = {"id": 1, "name": "a", "sacrifice_per_pay": 100, "after_tax_per_pay": 0}


def test_salary_on_picks_latest_effective_rate():
    assert salary_on(SCALE, "A.1", date(2026, 11, 19)) == 100_000
    assert salary_on(SCALE, "A.1", date(2027, 3, 1)) == 103_500
    with pytest.raises(ValueError):
        salary_on(SCALE, "A.1", date(2026, 2, 28))
    with pytest.raises(ValueError, match="no salary for step B.1 on 2026-11-19"):
        salary_on(SCALE, "B.1", date(2026, 11, 19))


def test_reference_date():
    d = date(2026, 11, 19)
    assert reference_date(2027, d) == date(2027, 3, 1)
    assert reference_date(None, d) == d


def test_leave_loading():
    assert (LEAVE_LOADING_RATE, LEAVE_LOADING_WEEKS) == (0.175, 4)
    assert leave_loading(52_000) == pytest.approx(700)


def test_tax_year_is_exposed():
    assert TAX_YEAR == "2026-27"


def test_salary_steps_sorted_naturally():
    rows = [{"step": s, "effective_from": "2026-03-01", "annual": 1} for s in ["A.10", "A.2", "A.2"]]
    assert salary_steps(rows) == ["A.2", "A.10"]


def test_missing_settings_requires_leave_loading():
    assert "include_leave_loading" in missing_settings(replace(SETTINGS, include_leave_loading=None))
    assert "include_leave_loading" not in missing_settings(SETTINGS)


def test_salary_step_replaces_yearly_gross_requirement():
    no_gross = replace(SETTINGS, yearly_gross=None)
    assert "yearly_gross" in missing_settings(no_gross)
    assert "yearly_gross" not in missing_settings(replace(no_gross, salary_step="A.1"))


def test_scenario_uses_settings_step_today_with_loading():
    s = replace(SETTINGS, yearly_gross=None, salary_step="A.1", include_leave_loading=True)
    [r] = scenario_results([PLAIN], s, 0, SCALE, TODAY)
    loading = 100_000 / 52 * 4 * 0.175
    assert r.salary == 100_000
    assert r.leave_loading == pytest.approx(loading)
    assert r.gross == pytest.approx(100_000 + loading)
    assert r.taxable == pytest.approx(r.gross - 2600)
    assert r.employer_super == 12_000


def test_scenario_year_uses_march_rate():
    s = replace(SETTINGS, salary_step="A.1")
    [r] = scenario_results([{**PLAIN, "year": 2027}], s, 0, SCALE, TODAY)
    assert (r.salary, r.year, r.salary_step) == (103_500, 2027, "A.1")


def test_scenario_own_step_overrides_settings():
    s = replace(SETTINGS, salary_step="A.1")
    [r] = scenario_results([{**PLAIN, "salary_step": "A.2"}], s, 0, SCALE, TODAY)
    assert r.salary == 110_000 and r.salary_step == "A.2"


def test_blank_scenario_step_falls_back_to_settings():
    s = replace(SETTINGS, salary_step="A.1")
    [r] = scenario_results([{**PLAIN, "salary_step": ""}], s, 0, SCALE, TODAY)
    assert r.salary == 100_000


def test_manual_gross_without_step():
    [r] = scenario_results([{**PLAIN, "year": 2030}], SETTINGS, 0, SCALE, TODAY)
    assert r.salary == 80_000 and r.leave_loading == 0 and r.gross == 80_000


def test_manual_gross_gets_leave_loading():
    s = replace(SETTINGS, include_leave_loading=True)
    [r] = scenario_results([PLAIN], s, 0, SCALE, TODAY)
    assert r.salary == 80_000
    assert r.gross == pytest.approx(80_000 + leave_loading(80_000))


def test_unknown_step_raises_with_scenario_name():
    with pytest.raises(ValueError, match="scenario a: no salary for step B.9"):
        scenario_results([{**PLAIN, "salary_step": "B.9"}], SETTINGS, 0, SCALE, TODAY)


def test_reduction_ignores_salary_growth_between_years():
    s = replace(SETTINGS, salary_step="A.1")
    contrib = {"sacrifice_per_pay": 100, "after_tax_per_pay": 50}
    zero = {"sacrifice_per_pay": 0, "after_tax_per_pay": 0}
    results = scenario_results(
        [
            {"id": 1, "name": "y26", "year": 2026, **contrib},
            {"id": 2, "name": "y27", "year": 2027, **contrib},
            {"id": 3, "name": "z26", "year": 2026, **zero},
            {"id": 4, "name": "z27", "year": 2027, **zero},
        ],
        s, 0, SCALE, TODAY,
    )
    y26, y27, z26, z27 = results
    assert y26.takehome_reduction_week == pytest.approx((z26.net_year - y26.net_year) / 52)
    assert y27.takehome_reduction_week == pytest.approx((z27.net_year - y27.net_year) / 52)
    assert y26.takehome_reduction_week != pytest.approx((y27.net_year - y26.net_year) / 52)
    assert y27.takehome_reduction_week != pytest.approx((y26.net_year - y27.net_year) / 52)
    assert z26.takehome_reduction_week == 0 and z27.takehome_reduction_week == 0
