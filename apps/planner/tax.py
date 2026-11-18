from dataclasses import dataclass

RATES = {
    "tax_brackets": [(0, 0.0), (18_200, 0.15), (45_000, 0.30), (135_000, 0.37), (190_000, 0.45)],
    "medicare_levy": 0.02,
    "lito_max": 700,
    "lito_full_until": 37_500,
    "lito_mid_until": 45_000,
    "lito_mid_value": 325,
    "lito_zero_at": 66_667,
    "lito_taper_1": 0.05,
    "lito_taper_2": 0.015,
    "mls_single": [(105_000, 0.0), (123_000, 0.01), (164_000, 0.0125), (float("inf"), 0.015)],
    "mls_family": [(210_000, 0.0), (246_000, 0.01), (328_000, 0.0125), (float("inf"), 0.015)],
    "mls_family_extra_per_child": 1_500,
    "concessional_cap": 32_500,
    "contributions_tax": 0.15,
    "fhss_year_limit": 15_000,
    "fhss_concessional_share": 0.85,
}


@dataclass(frozen=True)
class TaxSettings:
    include_medicare_levy: bool
    mls: str
    partner_income: float
    children: int


@dataclass(frozen=True)
class TaxResult:
    gross_tax: float
    lito: float
    medicare: float
    mls_income: float
    mls_rate: float
    mls: float
    total: float


def _gross_tax(taxable: float) -> float:
    brackets = RATES["tax_brackets"]
    uppers = [upper for upper, _ in brackets[1:]] + [float("inf")]
    return sum(
        (min(taxable, upper) - lower) * rate
        for (lower, rate), upper in zip(brackets, uppers)
        if taxable > lower
    )


def _lito_offset(t: float) -> float:
    r = RATES
    if t <= r["lito_full_until"]:
        return r["lito_max"]
    if t <= r["lito_mid_until"]:
        return r["lito_max"] - (t - r["lito_full_until"]) * r["lito_taper_1"]
    if t <= r["lito_zero_at"]:
        return max(0, r["lito_mid_value"] - (t - r["lito_mid_until"]) * r["lito_taper_2"])
    return 0


def _mls_rate(mls_income: float, s: TaxSettings) -> float:
    if s.mls == "none":
        return 0.0
    if s.mls == "family":
        tiers = RATES["mls_family"]
        extra = max(0, s.children - 1) * RATES["mls_family_extra_per_child"]
    else:
        tiers = RATES["mls_single"]
        extra = 0
    return next(rate for limit, rate in tiers if limit + extra >= mls_income)


def tax(taxable: float, sacrifice_year: float, s: TaxSettings) -> TaxResult:
    t = max(0.0, taxable)
    gross = _gross_tax(t)
    lito = min(gross, _lito_offset(t))
    medicare = t * RATES["medicare_levy"] if s.include_medicare_levy else 0.0
    mls_income = t + sacrifice_year + (s.partner_income if s.mls == "family" else 0)
    mls_rate = _mls_rate(mls_income, s)
    mls = t * mls_rate
    total = gross - lito + medicare + mls
    return TaxResult(gross, lito, medicare, mls_income, mls_rate, mls, total)
