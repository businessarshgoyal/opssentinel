"""Tests for the OpsSentinel synthetic data generator.

These tests confirm two things: the generator is deterministic for a fixed
seed, and the four seeded anomalies are actually present in the output so the
downstream agent has real signals to detect.
"""

import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "data"))

import generate  # noqa: E402


def build_ledger(seed: int = 7) -> generate.Ledger:
    """Run the in memory generation steps without touching disk."""
    import random

    rng = random.Random(seed)
    ledger = generate.Ledger()
    ledger.suppliers = generate.build_suppliers(rng)
    ledger.products = generate.build_products(rng, ledger.suppliers)
    ledger.warehouses = generate.build_warehouses()
    generate.build_orders_and_shipments(rng, ledger)
    generate.build_inventory(rng, ledger)
    generate.build_warehouse_spend(rng, ledger)
    generate.build_documents(rng, ledger)
    return ledger


def test_deterministic_row_counts(tmp_path):
    """The same seed must always produce the same number of rows."""
    first = generate.generate(7, str(tmp_path / "a"))
    second = generate.generate(7, str(tmp_path / "b"))
    assert first == second
    assert first["orders"] > 0
    assert first["documents"] > 0


def test_demand_spike_present():
    """Product P0007 must show a clear late window demand spike."""
    ledger = build_ledger()
    early_window_end = generate.END_DATE - timedelta(days=21)
    late_window_start = generate.END_DATE - timedelta(days=6)
    early = [
        o["quantity"]
        for o in ledger.orders
        if o["product_id"] == "P0007" and date.fromisoformat(o["order_date"]) <= early_window_end
    ]
    late = [
        o["quantity"]
        for o in ledger.orders
        if o["product_id"] == "P0007" and date.fromisoformat(o["order_date"]) >= late_window_start
    ]
    early_avg = sum(early) / len(early)
    late_avg = sum(late) / len(late)
    assert late_avg > early_avg * 2


def test_carrier_failure_present():
    """Carrier TransArc must show a much higher late rate in the final month."""
    ledger = build_ledger()
    cutoff = generate.END_DATE - timedelta(days=30)
    recent = [
        s
        for s in ledger.shipments
        if s["carrier"] == "TransArc" and date.fromisoformat(s["promised_date"]) >= cutoff
    ]
    late_rate = sum(1 for s in recent if s["late_days"] > 0) / len(recent)
    assert late_rate > 0.3


def test_quality_signal_present():
    """The failing supplier must accumulate negative reviews and tickets."""
    ledger = build_ledger()
    tickets = [d for d in ledger.documents if d["doc_type"] == "support_ticket"]
    assert len(tickets) > 5
    assert all(t["supplier_id"] == "SUP03" for t in tickets)


def test_cost_drift_present():
    """DC_WEST compute credits must trend upward in the final weeks."""
    ledger = build_ledger()
    cutoff = generate.END_DATE - timedelta(days=25)
    early = [
        r["compute_credits"]
        for r in ledger.warehouse_spend
        if r["dc_id"] == "DC_WEST" and date.fromisoformat(r["usage_date"]) < cutoff
    ]
    late = [
        r["compute_credits"]
        for r in ledger.warehouse_spend
        if r["dc_id"] == "DC_WEST" and date.fromisoformat(r["usage_date"]) >= cutoff
    ]
    assert sum(late) / len(late) > sum(early) / len(early) * 1.3
