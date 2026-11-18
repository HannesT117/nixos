from collections.abc import Mapping
from dataclasses import dataclass, replace
from typing import Optional

from tax import RATES, TaxSettings, tax

WEEKS_PER_YEAR = 52

PERIODS: dict[str, float] = {
    "Weekly": 1,
    "Fortnightly": 1 / 2,
    "Monthly": 12 / WEEKS_PER_YEAR,
    "Quarterly": 4 / WEEKS_PER_YEAR,
    "Yearly": 1 / WEEKS_PER_YEAR,
}

TRIP_PRICE_KEYS = ("transport_price", "insurance_price", "fuel_price", "accommodation_price")


def per_week(amount: float, period: str) -> float:
    if period not in PERIODS:
        raise ValueError(f"Unknown period: {period!r}")
    return amount * PERIODS[period]


def trip_total(trip: Mapping) -> float:
    return sum(trip.get(key) or 0 for key in TRIP_PRICE_KEYS)


def is_done(trip: Mapping) -> bool:
    return trip.get("fuel_price") is not None


@dataclass(frozen=True)
class TripSummary:
    done_trips: int
    average_trip: float
    trips_week: float


def valid_weeks_per_trip(value) -> bool:
    return value is not None and value > 0


def trip_summary(trips: list[Mapping], weeks_per_trip: float) -> TripSummary:
    done = [trip_total(t) for t in trips if is_done(t)]
    if not done:
        return TripSummary(0, 0, 0)
    if not valid_weeks_per_trip(weeks_per_trip):
        raise ValueError("weeks_per_trip must be positive")
    average = sum(done) / len(done)
    return TripSummary(len(done), average, average / weeks_per_trip)


@dataclass(frozen=True)
class ExpenseTotals:
    recurring_week: float
    trips_week: float
    total_week: float


def expense_totals(expenses: list[Mapping], trips_week: float) -> ExpenseTotals:
    recurring = sum(per_week(e["amount"], e["period"]) for e in expenses)
    return ExpenseTotals(recurring, trips_week, recurring + trips_week)


@dataclass(frozen=True)
class Settings:
    yearly_gross: Optional[float] = None
    pays_per_year: Optional[int] = None
    super_rate: Optional[float] = None
    include_medicare_levy: Optional[bool] = None
    mls: Optional[str] = None
    partner_income: Optional[float] = None
    children: Optional[int] = None
    savings_target_week: Optional[float] = None
    weeks_per_trip: Optional[float] = None
    baseline_scenario_id: Optional[int] = None


ALWAYS_REQUIRED = (
    "yearly_gross",
    "pays_per_year",
    "super_rate",
    "include_medicare_levy",
    "mls",
    "savings_target_week",
    "weeks_per_trip",
)


def missing_settings(s: Settings) -> list[str]:
    required = list(ALWAYS_REQUIRED)
    if s.mls == "family":
        required += ["partner_income", "children"]
    return [name for name in required if getattr(s, name) is None]


@dataclass(frozen=True)
class ScenarioResult:
    id: int
    name: str
    sacrifice_year: float
    after_tax_year: float
    taxable: float
    gross_tax: float
    lito: float
    medicare: float
    mls_rate: float
    mls: float
    total_tax: float
    net_year: float
    net_week: float
    takehome_reduction_week: float | None
    super_gain_year: float
    super_gain_week: float
    employer_super: float
    concessional_total: float
    cap_left: float
    fhss_release: float
    expenses_week: float
    cash_savings_week: float
    rest_week: float


def _scenario(sc: Mapping, s: Settings, total_week: float) -> ScenarioResult:
    pays = s.pays_per_year
    sacrifice = sc["sacrifice_per_pay"] * pays
    after_tax = sc["after_tax_per_pay"] * pays
    taxable = s.yearly_gross - sacrifice
    tax_settings = TaxSettings(
        s.include_medicare_levy,
        s.mls,
        s.partner_income or 0,
        s.children or 0,
    )
    t = tax(taxable, sacrifice, tax_settings)
    net_year = taxable - t.total - after_tax
    net_week = net_year / WEEKS_PER_YEAR
    super_gain_year = sacrifice * (1 - RATES["contributions_tax"]) + after_tax
    super_gain_week = super_gain_year / WEEKS_PER_YEAR
    employer_super = s.yearly_gross * s.super_rate
    concessional_total = employer_super + sacrifice
    limit = RATES["fhss_year_limit"]
    sacrifice_released = min(sacrifice, limit)
    fhss_release = sacrifice_released * RATES["fhss_concessional_share"] + min(
        after_tax, limit - sacrifice_released
    )
    cash_savings_week = max(0, s.savings_target_week - super_gain_week)
    return ScenarioResult(
        id=sc["id"],
        name=sc["name"],
        sacrifice_year=sacrifice,
        after_tax_year=after_tax,
        taxable=taxable,
        gross_tax=t.gross_tax,
        lito=t.lito,
        medicare=t.medicare,
        mls_rate=t.mls_rate,
        mls=t.mls,
        total_tax=t.total,
        net_year=net_year,
        net_week=net_week,
        takehome_reduction_week=None,
        super_gain_year=super_gain_year,
        super_gain_week=super_gain_week,
        employer_super=employer_super,
        concessional_total=concessional_total,
        cap_left=RATES["concessional_cap"] - concessional_total,
        fhss_release=fhss_release,
        expenses_week=total_week,
        cash_savings_week=cash_savings_week,
        rest_week=net_week - total_week - cash_savings_week,
    )


def scenario_results(scenarios: list[Mapping], s: Settings, total_week: float) -> list[ScenarioResult]:
    missing = missing_settings(s)
    if missing:
        raise ValueError(f"Missing settings: {', '.join(missing)}")
    results = [_scenario(sc, s, total_week) for sc in scenarios]
    baseline = next((r for r in results if r.id == s.baseline_scenario_id), None)
    if baseline is None:
        return results
    return [
        replace(r, takehome_reduction_week=(baseline.net_year - r.net_year) / WEEKS_PER_YEAR)
        for r in results
    ]
