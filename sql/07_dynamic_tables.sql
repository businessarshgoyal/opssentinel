-- OpsSentinel: anomaly detection pipeline as dynamic tables.
-- Each dynamic table compares a recent window against a trailing baseline and
-- emits a normalized anomaly row. A single ANOMALY_FEED unions them so the
-- action layer and the agent read from one place. Dynamic tables refresh
-- incrementally, which is what makes the monitoring continuous and hands off.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA APP;

-- Note: the reference date CTE is named refd because a shorter name collides
-- with the reserved ASOF join keyword.

-- Reference date derived from the data itself so results stay stable.
CREATE OR REPLACE VIEW APP.AS_OF AS
SELECT MAX(order_date) AS as_of_date FROM OPSSENTINEL.CORE.ORDERS;

-- Demand anomalies: recent 7 day average demand versus the prior 6 weeks.
CREATE OR REPLACE DYNAMIC TABLE APP.DEMAND_ANOMALIES
  TARGET_LAG = '1 hour'
  WAREHOUSE = OPSSENTINEL_WH
  AS
WITH refd AS (SELECT as_of_date FROM APP.AS_OF),
recent AS (
  SELECT o.product_id, AVG(o.quantity) AS recent_avg
  FROM OPSSENTINEL.CORE.ORDERS o, refd
  WHERE o.order_date > refd.as_of_date - 7
  GROUP BY o.product_id
),
baseline AS (
  SELECT o.product_id, AVG(o.quantity) AS base_avg
  FROM OPSSENTINEL.CORE.ORDERS o, refd
  WHERE o.order_date BETWEEN refd.as_of_date - 49 AND refd.as_of_date - 8
  GROUP BY o.product_id
)
SELECT
  'demand_spike' AS anomaly_type,
  r.product_id AS entity_id,
  p.product_name AS entity_name,
  ROUND(r.recent_avg, 1) AS recent_value,
  ROUND(b.base_avg, 1) AS baseline_value,
  ROUND(r.recent_avg / NULLIF(b.base_avg, 0), 2) AS ratio,
  CASE
    WHEN r.recent_avg > b.base_avg * 2 THEN 'high'
    WHEN r.recent_avg > b.base_avg * 1.4 THEN 'medium'
    ELSE 'low'
  END AS severity,
  'Recent daily demand is ' || ROUND(r.recent_avg / NULLIF(b.base_avg, 0), 2)
    || 'x the trailing six week baseline.' AS explanation
FROM recent r
JOIN baseline b ON r.product_id = b.product_id
JOIN OPSSENTINEL.CORE.PRODUCTS p ON p.product_id = r.product_id
WHERE r.recent_avg > b.base_avg * 1.4;

-- Carrier anomalies: recent late rate versus trailing baseline late rate.
CREATE OR REPLACE DYNAMIC TABLE APP.CARRIER_ANOMALIES
  TARGET_LAG = '1 hour'
  WAREHOUSE = OPSSENTINEL_WH
  AS
WITH refd AS (SELECT as_of_date FROM APP.AS_OF),
recent AS (
  SELECT s.carrier, AVG(IFF(s.late_days > 0, 1, 0)) AS recent_late
  FROM OPSSENTINEL.CORE.SHIPMENTS s, refd
  WHERE s.promised_date > refd.as_of_date - 14
  GROUP BY s.carrier
),
baseline AS (
  SELECT s.carrier, AVG(IFF(s.late_days > 0, 1, 0)) AS base_late
  FROM OPSSENTINEL.CORE.SHIPMENTS s, refd
  WHERE s.promised_date BETWEEN refd.as_of_date - 90 AND refd.as_of_date - 15
  GROUP BY s.carrier
)
SELECT
  'carrier_delay' AS anomaly_type,
  r.carrier AS entity_id,
  r.carrier AS entity_name,
  ROUND(r.recent_late, 3) AS recent_value,
  ROUND(b.base_late, 3) AS baseline_value,
  ROUND(r.recent_late / NULLIF(b.base_late, 0), 2) AS ratio,
  CASE
    WHEN r.recent_late > 0.35 THEN 'high'
    WHEN r.recent_late > 0.2 THEN 'medium'
    ELSE 'low'
  END AS severity,
  'Recent late rate is ' || ROUND(r.recent_late * 100, 1)
    || ' percent versus a baseline of ' || ROUND(b.base_late * 100, 1)
    || ' percent.' AS explanation
FROM recent r
JOIN baseline b ON r.carrier = b.carrier
WHERE r.recent_late > GREATEST(b.base_late * 1.5, 0.2);

-- Inventory anomalies: products at or below the reorder point recently.
CREATE OR REPLACE DYNAMIC TABLE APP.INVENTORY_ANOMALIES
  TARGET_LAG = '1 hour'
  WAREHOUSE = OPSSENTINEL_WH
  AS
WITH refd AS (SELECT as_of_date FROM APP.AS_OF),
latest AS (
  SELECT i.product_id, i.dc_id, i.on_hand_units, i.reorder_point,
         ROW_NUMBER() OVER (PARTITION BY i.product_id, i.dc_id ORDER BY i.snapshot_date DESC) AS rn
  FROM OPSSENTINEL.CORE.INVENTORY i, refd
  WHERE i.snapshot_date <= refd.as_of_date
)
SELECT
  'stockout_risk' AS anomaly_type,
  l.product_id AS entity_id,
  p.product_name AS entity_name,
  l.on_hand_units AS recent_value,
  l.reorder_point AS baseline_value,
  ROUND(l.on_hand_units / NULLIF(l.reorder_point, 0), 2) AS ratio,
  CASE
    WHEN l.on_hand_units < l.reorder_point * 0.5 THEN 'high'
    WHEN l.on_hand_units < l.reorder_point THEN 'medium'
    ELSE 'low'
  END AS severity,
  'On hand units at ' || l.dc_id || ' are '
    || ROUND(l.on_hand_units / NULLIF(l.reorder_point, 0) * 100, 0)
    || ' percent of the reorder point.' AS explanation
FROM latest l
JOIN OPSSENTINEL.CORE.PRODUCTS p ON p.product_id = l.product_id
WHERE l.rn = 1 AND l.on_hand_units < l.reorder_point;

-- Cost anomalies: recent compute spend versus trailing baseline per DC.
CREATE OR REPLACE DYNAMIC TABLE APP.COST_ANOMALIES
  TARGET_LAG = '1 hour'
  WAREHOUSE = OPSSENTINEL_WH
  AS
WITH refd AS (SELECT as_of_date FROM APP.AS_OF),
recent AS (
  SELECT w.dc_id, AVG(w.compute_credits) AS recent_avg
  FROM OPSSENTINEL.CORE.WAREHOUSE_SPEND w, refd
  WHERE w.usage_date > refd.as_of_date - 10
  GROUP BY w.dc_id
),
baseline AS (
  SELECT w.dc_id, AVG(w.compute_credits) AS base_avg
  FROM OPSSENTINEL.CORE.WAREHOUSE_SPEND w, refd
  WHERE w.usage_date BETWEEN refd.as_of_date - 70 AND refd.as_of_date - 11
  GROUP BY w.dc_id
)
SELECT
  'cost_drift' AS anomaly_type,
  r.dc_id AS entity_id,
  d.dc_name AS entity_name,
  ROUND(r.recent_avg, 1) AS recent_value,
  ROUND(b.base_avg, 1) AS baseline_value,
  ROUND(r.recent_avg / NULLIF(b.base_avg, 0), 2) AS ratio,
  CASE
    WHEN r.recent_avg > b.base_avg * 1.6 THEN 'high'
    WHEN r.recent_avg > b.base_avg * 1.25 THEN 'medium'
    ELSE 'low'
  END AS severity,
  'Recent compute credits are ' || ROUND(r.recent_avg / NULLIF(b.base_avg, 0), 2)
    || 'x the trailing baseline with no matching throughput gain.' AS explanation
FROM recent r
JOIN baseline b ON r.dc_id = b.dc_id
JOIN OPSSENTINEL.CORE.WAREHOUSES d ON d.dc_id = r.dc_id
WHERE r.recent_avg > b.base_avg * 1.25;

-- Unified feed the rest of the system reads from.
CREATE OR REPLACE DYNAMIC TABLE APP.ANOMALY_FEED
  TARGET_LAG = '1 hour'
  WAREHOUSE = OPSSENTINEL_WH
  AS
SELECT anomaly_type, entity_id, entity_name, recent_value, baseline_value, ratio, severity, explanation FROM APP.DEMAND_ANOMALIES
UNION ALL
SELECT anomaly_type, entity_id, entity_name, recent_value, baseline_value, ratio, severity, explanation FROM APP.CARRIER_ANOMALIES
UNION ALL
SELECT anomaly_type, entity_id, entity_name, recent_value, baseline_value, ratio, severity, explanation FROM APP.INVENTORY_ANOMALIES
UNION ALL
SELECT anomaly_type, entity_id, entity_name, recent_value, baseline_value, ratio, severity, explanation FROM APP.COST_ANOMALIES;

SELECT * FROM APP.ANOMALY_FEED ORDER BY severity, anomaly_type;
