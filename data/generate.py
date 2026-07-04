"""Synthetic data generator for OpsSentinel.

This module produces a coherent, deterministic supply chain and operations
dataset that mixes structured records (suppliers, products, inventory, orders,
shipments, warehouse spend) with unstructured documents (supplier emails,
carrier incident reports, customer reviews, support tickets, market news).

The data is intentionally seeded with realistic anomalies so that the
OpsSentinel agent has something meaningful to reason about:

  1. A demand spike on one product that is not matched by inventory.
  2. A supplier whose quality degrades, visible in reviews and support tickets.
  3. A carrier whose on time performance collapses, backed by incident reports.
  4. A warehouse whose compute spend drifts upward without added throughput.

Everything is generated from the Python standard library only, so the script
runs on any machine with no third party packages. Output is written as CSV
files (structured tables) plus one JSONL file (unstructured documents) that the
SQL loaders in the sql directory pick up.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import random
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

# The reference window ends on a fixed date so that generated data and the
# demo narrative stay stable across runs regardless of the wall clock.
WINDOW_DAYS = 120
END_DATE = date(2026, 6, 30)
START_DATE = END_DATE - timedelta(days=WINDOW_DAYS - 1)

REGIONS = ["North America", "Europe", "APJ", "LATAM"]
CATEGORIES = ["Beverages", "Snacks", "Personal Care", "Home Care"]
CARRIERS = ["FleetLink", "TransArc", "BluePort", "NorthRail"]


@dataclass
class Ledger:
    """Container that accumulates every generated row before it is written."""

    suppliers: list = field(default_factory=list)
    products: list = field(default_factory=list)
    warehouses: list = field(default_factory=list)
    inventory: list = field(default_factory=list)
    orders: list = field(default_factory=list)
    shipments: list = field(default_factory=list)
    warehouse_spend: list = field(default_factory=list)
    documents: list = field(default_factory=list)


def daterange(start: date, end: date):
    """Yield every date from start to end inclusive."""
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def build_suppliers(rng: random.Random) -> list:
    """Create the supplier master. Supplier SUP03 is the quality risk case."""
    names = [
        ("SUP01", "Aurora Foods", "United States", 0.97),
        ("SUP02", "Meridian Beverage", "Germany", 0.95),
        ("SUP03", "Cedar Valley Goods", "Vietnam", 0.9),
        ("SUP04", "Northwind Supply", "Canada", 0.96),
        ("SUP05", "Solace Personal Care", "India", 0.94),
    ]
    suppliers = []
    for supplier_id, name, country, reliability in names:
        category = rng.choice(CATEGORIES)
        suppliers.append(
            {
                "supplier_id": supplier_id,
                "supplier_name": name,
                "country": country,
                "primary_category": category,
                "reliability_baseline": reliability,
            }
        )
    return suppliers


def build_products(rng: random.Random, suppliers: list) -> list:
    """Create the product catalog. Product P0007 is the demand spike case."""
    products = []
    catalog = [
        ("Sparkling Water 12pk", "Beverages"),
        ("Cold Brew Concentrate", "Beverages"),
        ("Trail Mix Family Bag", "Snacks"),
        ("Protein Crackers", "Snacks"),
        ("Herbal Shampoo", "Personal Care"),
        ("Bamboo Toothbrush", "Personal Care"),
        ("Citrus Dish Soap", "Home Care"),
        ("Laundry Pods 60ct", "Home Care"),
        ("Oat Milk Barista", "Beverages"),
        ("Almond Butter Cups", "Snacks"),
    ]
    for index, (name, category) in enumerate(catalog, start=1):
        product_id = "P%04d" % index
        supplier = rng.choice(suppliers)
        unit_cost = round(rng.uniform(1.5, 9.5), 2)
        products.append(
            {
                "product_id": product_id,
                "product_name": name,
                "category": category,
                "supplier_id": supplier["supplier_id"],
                "unit_cost": unit_cost,
                "base_daily_demand": rng.randint(180, 420),
            }
        )
    # Force the demand spike product to be sourced from the risky supplier so
    # the anomalies compound into one coherent story for the agent.
    products[6]["supplier_id"] = "SUP03"
    return products


def build_warehouses() -> list:
    """Create distribution centers. DC_WEST is the compute drift case."""
    return [
        {"dc_id": "DC_WEST", "dc_name": "West Regional DC", "region": "North America"},
        {"dc_id": "DC_EAST", "dc_name": "East Regional DC", "region": "North America"},
        {"dc_id": "DC_EU", "dc_name": "Rotterdam DC", "region": "Europe"},
        {"dc_id": "DC_APJ", "dc_name": "Singapore DC", "region": "APJ"},
    ]


def demand_for(product: dict, day: date, rng: random.Random) -> int:
    """Return units ordered for a product on a given day, with a seeded spike."""
    base = product["base_daily_demand"]
    weekday_factor = 1.15 if day.weekday() < 5 else 0.7
    noise = rng.uniform(0.85, 1.15)
    units = base * weekday_factor * noise
    # Product P0007 sees a sustained demand spike in the final three weeks.
    if product["product_id"] == "P0007" and day >= END_DATE - timedelta(days=20):
        ramp = 1.0 + 2.4 * ((day - (END_DATE - timedelta(days=20))).days / 20.0)
        units *= ramp
    return max(0, int(round(units)))


def build_orders_and_shipments(rng: random.Random, ledger: Ledger) -> None:
    """Generate daily orders and their downstream shipments with late signals."""
    order_counter = 0
    shipment_counter = 0
    for day in daterange(START_DATE, END_DATE):
        for product in ledger.products:
            units = demand_for(product, day, rng)
            if units == 0:
                continue
            dc = rng.choice(ledger.warehouses)
            order_counter += 1
            order_id = "ORD%06d" % order_counter
            ledger.orders.append(
                {
                    "order_id": order_id,
                    "order_date": day.isoformat(),
                    "product_id": product["product_id"],
                    "dc_id": dc["dc_id"],
                    "customer_region": rng.choice(REGIONS),
                    "quantity": units,
                    "unit_price": round(product["unit_cost"] * rng.uniform(1.4, 1.9), 2),
                }
            )

            carrier = rng.choice(CARRIERS)
            promised = day + timedelta(days=rng.randint(2, 5))
            late_days = compute_late_days(carrier, day, rng)
            actual = promised + timedelta(days=late_days)
            shipment_counter += 1
            ledger.shipments.append(
                {
                    "shipment_id": "SHP%06d" % shipment_counter,
                    "order_id": order_id,
                    "supplier_id": product["supplier_id"],
                    "carrier": carrier,
                    "promised_date": promised.isoformat(),
                    "actual_date": actual.isoformat(),
                    "late_days": late_days,
                    "status": "late" if late_days > 0 else "on_time",
                }
            )


def compute_late_days(carrier: str, day: date, rng: random.Random) -> int:
    """Return how many days late a shipment is, with a seeded carrier failure."""
    baseline = 0.08
    # Carrier TransArc degrades sharply in the final month of the window.
    if carrier == "TransArc" and day >= END_DATE - timedelta(days=30):
        baseline = 0.55
    if rng.random() < baseline:
        return rng.randint(1, 6)
    return 0


def build_inventory(rng: random.Random, ledger: Ledger) -> None:
    """Generate weekly inventory snapshots with a seeded stockout risk."""
    for day in daterange(START_DATE, END_DATE):
        if day.weekday() != 0:
            continue
        for product in ledger.products:
            for dc in ledger.warehouses:
                base = product["base_daily_demand"]
                safety_stock = base * 4
                reorder_point = base * 6
                on_hand = int(base * rng.uniform(5, 12))
                # The spike product runs dangerously low late in the window.
                if product["product_id"] == "P0007" and day >= END_DATE - timedelta(days=14):
                    on_hand = int(base * rng.uniform(1.0, 2.0))
                ledger.inventory.append(
                    {
                        "snapshot_date": day.isoformat(),
                        "dc_id": dc["dc_id"],
                        "product_id": product["product_id"],
                        "on_hand_units": on_hand,
                        "reorder_point": reorder_point,
                        "safety_stock": safety_stock,
                    }
                )


def build_warehouse_spend(rng: random.Random, ledger: Ledger) -> None:
    """Generate daily compute spend per DC with a seeded cost drift."""
    for day in daterange(START_DATE, END_DATE):
        for dc in ledger.warehouses:
            base_credits = {"DC_WEST": 42, "DC_EAST": 38, "DC_EU": 30, "DC_APJ": 26}[dc["dc_id"]]
            credits = base_credits * rng.uniform(0.92, 1.08)
            # DC_WEST compute spend drifts upward without added throughput.
            if dc["dc_id"] == "DC_WEST" and day >= END_DATE - timedelta(days=25):
                drift = 1.0 + 1.6 * ((day - (END_DATE - timedelta(days=25))).days / 25.0)
                credits *= drift
            ledger.warehouse_spend.append(
                {
                    "usage_date": day.isoformat(),
                    "dc_id": dc["dc_id"],
                    "compute_credits": round(credits, 2),
                    "credit_price_usd": 3.0,
                }
            )


def add_document(ledger: Ledger, doc_type: str, source: str, created: date, body: str,
                 supplier_id: str = "", product_id: str = "", carrier: str = "") -> None:
    """Append one unstructured document row to the ledger."""
    doc_id = "DOC%05d" % (len(ledger.documents) + 1)
    ledger.documents.append(
        {
            "doc_id": doc_id,
            "doc_type": doc_type,
            "source": source,
            "created_date": created.isoformat(),
            "supplier_id": supplier_id,
            "product_id": product_id,
            "carrier": carrier,
            "body": body,
        }
    )


def build_documents(rng: random.Random, ledger: Ledger) -> None:
    """Generate the unstructured corpus that corroborates the anomalies."""
    # Supplier quality decline for SUP03, visible in reviews and tickets.
    negative_reviews = [
        "The seal was broken on arrival and the product tasted stale.",
        "Third order in a row with damaged packaging, very disappointed.",
        "Quality has dropped noticeably compared to last quarter.",
        "Found a foreign particle in the pack, reporting for safety.",
        "Returned the whole case, the batch smelled off.",
    ]
    positive_reviews = [
        "Great value and fast delivery, will buy again.",
        "Exactly as described, packaging was solid.",
        "Consistent quality, my household staple.",
        "Happy with the freshness and the taste.",
    ]
    for day in daterange(START_DATE, END_DATE):
        review_count = rng.randint(2, 5)
        for _ in range(review_count):
            product = rng.choice(ledger.products)
            supplier_id = product["supplier_id"]
            recent = day >= END_DATE - timedelta(days=25)
            if supplier_id == "SUP03" and recent and rng.random() < 0.75:
                body = rng.choice(negative_reviews)
            else:
                body = rng.choice(positive_reviews)
            add_document(
                ledger,
                doc_type="customer_review",
                source="reviews_portal",
                created=day,
                body=body,
                supplier_id=supplier_id,
                product_id=product["product_id"],
            )

    # Support tickets that spike for the failing supplier and product.
    ticket_templates = [
        "Customer reports leaking units from lot {lot}. Requesting replacement and root cause.",
        "Repeat complaint about damaged {product} shipments this week.",
        "Escalation: retail partner threatening chargeback over defect rate on {product}.",
        "Quality hold requested on incoming {product} pending supplier review.",
    ]
    for day in daterange(END_DATE - timedelta(days=25), END_DATE):
        if rng.random() < 0.6:
            add_document(
                ledger,
                doc_type="support_ticket",
                source="zendesk",
                created=day,
                body=rng.choice(ticket_templates).format(lot=rng.randint(1000, 9999), product="Citrus Dish Soap"),
                supplier_id="SUP03",
                product_id="P0007",
            )

    # Carrier incident reports that explain the on time collapse for TransArc.
    incident_templates = [
        "Regional hub congestion delayed outbound freight by two days.",
        "Driver shortage in the corridor pushed delivery windows back.",
        "Weather event closed the primary route, rerouting added transit time.",
        "Sorting facility outage created a backlog of pending parcels.",
    ]
    for day in daterange(END_DATE - timedelta(days=30), END_DATE):
        if rng.random() < 0.5:
            add_document(
                ledger,
                doc_type="carrier_incident",
                source="carrier_edi",
                created=day,
                body=rng.choice(incident_templates),
                carrier="TransArc",
            )

    # Supplier emails that hint at upstream constraints.
    supplier_email_templates = [
        "We are experiencing raw material constraints and may extend lead times by one week.",
        "Please note a temporary price adjustment on the next purchase order.",
        "Our QA team is investigating a batch flagged during outbound inspection.",
        "Capacity is limited this month, we recommend advancing critical orders.",
    ]
    for day in daterange(START_DATE, END_DATE):
        if rng.random() < 0.15:
            supplier = rng.choice(ledger.suppliers)
            add_document(
                ledger,
                doc_type="supplier_email",
                source="inbox",
                created=day,
                body=rng.choice(supplier_email_templates),
                supplier_id=supplier["supplier_id"],
            )

    # Market news snippets for external context.
    news_templates = [
        "Freight indices rose this week as fuel costs climbed across the region.",
        "Consumer demand for sparkling beverages is trending up in urban markets.",
        "A packaging supplier announced a recall affecting several brands.",
        "Port operations returned to normal after a brief labor action.",
    ]
    for day in daterange(START_DATE, END_DATE):
        if rng.random() < 0.1:
            add_document(
                ledger,
                doc_type="market_news",
                source="news_feed",
                created=day,
                body=rng.choice(news_templates),
            )


def write_csv(path: str, rows: list) -> None:
    """Write a list of dict rows to a CSV file with a stable header order."""
    if not rows:
        return
    fieldnames = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_jsonl(path: str, rows: list) -> None:
    """Write a list of dict rows to a newline delimited JSON file."""
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False))
            handle.write("\n")


def generate(seed: int, out_dir: str) -> dict:
    """Build the full dataset and write every file. Returns a row count summary."""
    rng = random.Random(seed)
    ledger = Ledger()
    ledger.suppliers = build_suppliers(rng)
    ledger.products = build_products(rng, ledger.suppliers)
    ledger.warehouses = build_warehouses()
    build_orders_and_shipments(rng, ledger)
    build_inventory(rng, ledger)
    build_warehouse_spend(rng, ledger)
    build_documents(rng, ledger)

    os.makedirs(out_dir, exist_ok=True)
    write_csv(os.path.join(out_dir, "suppliers.csv"), ledger.suppliers)
    write_csv(os.path.join(out_dir, "products.csv"), ledger.products)
    write_csv(os.path.join(out_dir, "warehouses.csv"), ledger.warehouses)
    write_csv(os.path.join(out_dir, "inventory.csv"), ledger.inventory)
    write_csv(os.path.join(out_dir, "orders.csv"), ledger.orders)
    write_csv(os.path.join(out_dir, "shipments.csv"), ledger.shipments)
    write_csv(os.path.join(out_dir, "warehouse_spend.csv"), ledger.warehouse_spend)
    write_jsonl(os.path.join(out_dir, "documents.jsonl"), ledger.documents)

    summary = {
        "suppliers": len(ledger.suppliers),
        "products": len(ledger.products),
        "warehouses": len(ledger.warehouses),
        "inventory": len(ledger.inventory),
        "orders": len(ledger.orders),
        "shipments": len(ledger.shipments),
        "warehouse_spend": len(ledger.warehouse_spend),
        "documents": len(ledger.documents),
    }
    write_jsonl(os.path.join(out_dir, "summary.json"), [summary])
    return summary


def main() -> None:
    """Command line entry point for the generator."""
    parser = argparse.ArgumentParser(description="Generate OpsSentinel demo data.")
    parser.add_argument("--seed", type=int, default=7, help="random seed for reproducibility")
    parser.add_argument(
        "--out",
        type=str,
        default=os.path.join(os.path.dirname(__file__), "generated"),
        help="output directory for generated files",
    )
    args = parser.parse_args()
    summary = generate(args.seed, args.out)
    stamp = datetime.now().isoformat(timespec="seconds")
    print("OpsSentinel data generated at %s" % stamp)
    for name, count in summary.items():
        print("  %-16s %d rows" % (name, count))


if __name__ == "__main__":
    main()
