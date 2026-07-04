-- OpsSentinel: semantic view for Cortex Analyst.
-- The semantic view is what lets users and the agent ask questions in plain
-- language. It maps business concepts (revenue, late rate, stockout risk) onto
-- the physical tables so Cortex Analyst can generate correct SQL on its own.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.OPS_SEMANTIC
  TABLES (
    orders AS OPSSENTINEL.CORE.ORDERS
      PRIMARY KEY (order_id)
      WITH SYNONYMS ('sales', 'demand')
      COMMENT = 'Customer orders, one row per order line.',
    shipments AS OPSSENTINEL.CORE.SHIPMENTS
      PRIMARY KEY (shipment_id)
      WITH SYNONYMS ('deliveries', 'freight')
      COMMENT = 'Outbound shipments with promised and actual delivery dates.',
    inventory AS OPSSENTINEL.CORE.INVENTORY
      WITH SYNONYMS ('stock', 'on hand')
      COMMENT = 'Weekly inventory snapshots by distribution center.',
    products AS OPSSENTINEL.CORE.PRODUCTS
      PRIMARY KEY (product_id)
      COMMENT = 'Product catalog.',
    suppliers AS OPSSENTINEL.CORE.SUPPLIERS
      PRIMARY KEY (supplier_id)
      COMMENT = 'Supplier master.',
    warehouses AS OPSSENTINEL.CORE.WAREHOUSES
      PRIMARY KEY (dc_id)
      COMMENT = 'Distribution centers.',
    spend AS OPSSENTINEL.CORE.WAREHOUSE_SPEND
      COMMENT = 'Daily compute credit usage per distribution center.'
  )
  RELATIONSHIPS (
    orders_to_product AS orders (product_id) REFERENCES products (product_id),
    orders_to_dc AS orders (dc_id) REFERENCES warehouses (dc_id),
    shipments_to_order AS shipments (order_id) REFERENCES orders (order_id),
    shipments_to_supplier AS shipments (supplier_id) REFERENCES suppliers (supplier_id),
    inventory_to_product AS inventory (product_id) REFERENCES products (product_id),
    inventory_to_dc AS inventory (dc_id) REFERENCES warehouses (dc_id),
    product_to_supplier AS products (supplier_id) REFERENCES suppliers (supplier_id),
    spend_to_dc AS spend (dc_id) REFERENCES warehouses (dc_id)
  )
  FACTS (
    orders.line_revenue AS orders.quantity * orders.unit_price,
    shipments.is_late AS IFF(shipments.late_days > 0, 1, 0),
    inventory.below_reorder AS IFF(inventory.on_hand_units < inventory.reorder_point, 1, 0),
    spend.usd_cost AS spend.compute_credits * spend.credit_price_usd
  )
  DIMENSIONS (
    orders.order_date AS orders.order_date WITH SYNONYMS ('date', 'day'),
    orders.customer_region AS orders.customer_region WITH SYNONYMS ('region', 'market'),
    products.category AS products.category,
    products.product_name AS products.product_name,
    suppliers.supplier_name AS suppliers.supplier_name,
    shipments.carrier AS shipments.carrier,
    warehouses.dc_name AS warehouses.dc_name,
    warehouses.region AS warehouses.region
  )
  METRICS (
    orders.total_revenue AS SUM(orders.line_revenue)
      WITH SYNONYMS ('sales', 'revenue')
      COMMENT = 'Total order revenue.',
    orders.total_units AS SUM(orders.quantity)
      COMMENT = 'Total units ordered.',
    shipments.late_rate AS AVG(shipments.is_late)
      WITH SYNONYMS ('on time performance', 'delivery reliability')
      COMMENT = 'Share of shipments delivered after the promised date.',
    shipments.avg_late_days AS AVG(shipments.late_days)
      COMMENT = 'Average days late across shipments.',
    inventory.stockout_risk_rate AS AVG(inventory.below_reorder)
      WITH SYNONYMS ('stockout risk')
      COMMENT = 'Share of inventory snapshots below the reorder point.',
    spend.total_compute_cost AS SUM(spend.usd_cost)
      WITH SYNONYMS ('compute spend', 'cost')
      COMMENT = 'Total compute cost in US dollars.'
  )
  COMMENT = 'OpsSentinel operations semantic model for Cortex Analyst.';

-- Confirm the view was created and is visible to Cortex Analyst.
SHOW SEMANTIC VIEWS LIKE 'OPS_SEMANTIC' IN SCHEMA APP;
