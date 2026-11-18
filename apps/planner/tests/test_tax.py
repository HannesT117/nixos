import pytest

from tax import TaxSettings, tax

CASES = [
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
def test_tax_matches_reference(case):
    _, taxable, sacrifice, levy, mls, partner, children, gross, lito, medicare, rate, mls_amt, total = case
    r = tax(taxable, sacrifice, TaxSettings(levy, mls, partner, children))
    assert r.gross_tax == pytest.approx(gross, abs=0.01)
    assert r.lito == pytest.approx(lito, abs=0.01)
    assert r.medicare == pytest.approx(medicare, abs=0.01)
    assert r.mls_rate == pytest.approx(rate, abs=0.01)
    assert r.mls == pytest.approx(mls_amt, abs=0.01)
    assert r.total == pytest.approx(total, abs=0.01)


def test_negative_taxable_pays_no_tax():
    r = tax(-1000, 0, TaxSettings(True, "single", 0, 0))
    assert (r.gross_tax, r.medicare, r.mls, r.total) == (0, 0, 0, 0)
