import pytest

from tax import TaxSettings, tax

CASES = [
    ("low", 15000, 0, False, "none", 0, 0, 0.00, 0.00, 0.00, 0.0, 0.00, 0.00, 15000),
    ("lito_taper_1", 40000, 0, False, "none", 0, 0, 3270.00, 575.00, 0.00, 0.0, 0.00, 2695.00, 40000),
    ("lito_taper_2", 60000, 0, True, "none", 0, 0, 8520.00, 100.00, 1200.00, 0.0, 0.00, 9620.00, 60000),
    ("bracket_37", 150000, 0, True, "none", 0, 0, 36570.00, 0.00, 3000.00, 0.0, 0.00, 39570.00, 150000),
    ("bracket_45", 200000, 0, False, "none", 0, 0, 55870.00, 0.00, 0.00, 0.0, 0.00, 55870.00, 200000),
    ("mls_single_edge", 105000, 0, False, "single", 0, 0, 22020.00, 0.00, 0.00, 0.0, 0.00, 22020.00, 105000),
    ("mls_single_over", 100000, 5001, False, "single", 0, 0, 20520.00, 0.00, 0.00, 0.01, 1000.00, 21520.00, 105001),
    ("mls_family_kids", 90000, 10000, True, "family", 130000, 3, 17520.00, 0.00, 1800.00, 0.01, 900.00, 20220.00, 230000),
    ("lito_full_positive_tax", 30000, 0, False, "none", 0, 0, 1770.00, 700.00, 0.00, 0.0, 0.00, 1070.00, 30000),
    ("lito_edge_full", 37500, 0, False, "none", 0, 0, 2895.00, 700.00, 0.00, 0.0, 0.00, 2195.00, 37500),
    ("lito_edge_mid", 45000, 0, False, "none", 0, 0, 4020.00, 325.00, 0.00, 0.0, 0.00, 3695.00, 45000),
    ("lito_edge_zero", 66667, 0, False, "none", 0, 0, 10520.10, 0.00, 0.00, 0.0, 0.00, 10520.10, 66667),
    ("mls_single_1_25", 130000, 0, False, "single", 0, 0, 29520.00, 0.00, 0.00, 0.0125, 1625.00, 31145.00, 130000),
    ("mls_single_1_5", 170000, 0, False, "single", 0, 0, 43970.00, 0.00, 0.00, 0.015, 2550.00, 46520.00, 170000),
    ("mls_family_one_child", 150000, 0, False, "family", 80000, 1, 36570.00, 0.00, 0.00, 0.01, 1500.00, 38070.00, 230000),
    ("mls_family_edge_extra", 120000, 0, False, "family", 93000, 3, 26520.00, 0.00, 0.00, 0.0, 0.00, 26520.00, 213000),
]


@pytest.mark.parametrize("case", CASES, ids=[c[0] for c in CASES])
def test_tax_matches_reference(case):
    _, taxable, sacrifice, levy, mls, partner, children, gross, lito, medicare, rate, mls_amt, total, mls_income = case
    r = tax(taxable, sacrifice, TaxSettings(levy, mls, partner, children))
    assert r.gross_tax == pytest.approx(gross, abs=0.01)
    assert r.lito == pytest.approx(lito, abs=0.01)
    assert r.medicare == pytest.approx(medicare, abs=0.01)
    assert r.mls_rate == pytest.approx(rate, abs=0.01)
    assert r.mls == pytest.approx(mls_amt, abs=0.01)
    assert r.total == pytest.approx(total, abs=0.01)
    assert r.mls_income == mls_income


def test_negative_taxable_pays_no_tax():
    r = tax(-1000, 0, TaxSettings(True, "single", 0, 0))
    assert (r.gross_tax, r.medicare, r.mls, r.total) == (0, 0, 0, 0)
