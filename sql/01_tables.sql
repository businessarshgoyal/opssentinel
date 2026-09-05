-- OpsSentinel: structured operational tables.
-- These mirror the CSV files produced by data/generate.py.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA CORE;

CREATE OR REPLACE TABLE SUPPLIERS (
  supplier_id           STRING,
  supplier_name         STRING,
  country               STRING,
  primary_category      STRING,
  reliability_baseline  FLOAT
);

CREATE OR REPLACE TABLE PRODUCTS (
  product_id         STRING,
  product_name       STRING,
  category           STRING,
  supplier_id        STRING,
  unit_cost          FLOAT,
  base_daily_demand  NUMBER
);

CREATE OR REPLACE TABLE WAREHOUSES (
  dc_id    STRING,
  dc_name  STRING,
  region   STRING
);

CREATE OR REPLACE TABLE INVENTORY (
  snapshot_date   DATE,
  dc_id           STRING,
  product_id      STRING,
  on_hand_units   NUMBER,
  reorder_point   NUMBER,
  safety_stock    NUMBER
);

CREATE OR REPLACE TABLE ORDERS (
  order_id         STRING,
  order_date       DATE,
  product_id       STRING,
  dc_id            STRING,
  customer_region  STRING,
  quantity         NUMBER,
  unit_price       FLOAT
);

CREATE OR REPLACE TABLE SHIPMENTS (
  shipment_id    STRING,
  order_id       STRING,
  supplier_id    STRING,
  carrier        STRING,
  promised_date  DATE,
  actual_date    DATE,
  late_days      NUMBER,
  status         STRING
);

CREATE OR REPLACE TABLE WAREHOUSE_SPEND (
  usage_date        DATE,
  dc_id             STRING,
  compute_credits   FLOAT,
  credit_price_usd  FLOAT
);
