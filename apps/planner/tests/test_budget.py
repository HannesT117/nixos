from dataclasses import replace

import pytest

from budget import (
    PERIODS,
    ExpenseTotals,
    Settings,
    TripSummary,
    valid_weeks_per_trip,
    expense_totals,
    is_done,
    per_week,
    scenario_results,
    trip_summary,
    trip_total,
)
from tax import RATES, TaxSettings, tax


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
                    mls="none", savings_target_week=200, weeks_per_trip=2, baseline_scenario_id=1)


def test_scenario_matches_tax_module_and_rules():
    [base, s100] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0},
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
    assert s100.takehome_reduction_week == pytest.approx((base.net_year - s100.net_year) / 52)


def test_takehome_reduction_without_baseline():
    [r] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}],
                           replace(SETTINGS, baseline_scenario_id=None), 0)
    assert r.takehome_reduction_week is None


def test_takehome_reduction_with_unknown_baseline_id():
    [r] = scenario_results([{"id": 1, "name": "a", "sacrifice_per_pay": 0, "after_tax_per_pay": 0}],
                           replace(SETTINGS, baseline_scenario_id=9), 0)
    assert r.takehome_reduction_week is None


def test_empty_scenarios_with_complete_settings():
    assert scenario_results([], SETTINGS, 0) == []


def test_family_mls_requires_partner_income_and_children():
    with pytest.raises(ValueError, match="partner_income.*children"):
        scenario_results([], replace(SETTINGS, mls="family"), 0)
