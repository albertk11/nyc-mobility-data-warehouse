-- =============================================================================
-- 05_performance_tuning.sql
-- Purpose: Benchmark query performance BEFORE and AFTER creating B-Tree indexes
--          on Fact Table Foreign Keys and temporal columns using
--          EXPLAIN (ANALYZE, BUFFERS).
-- =============================================================================

-- =============================================================================
-- STEP 1: Ensure clean baseline (drop indexes if re-running for benchmark)
-- =============================================================================
DROP INDEX IF EXISTS idx_fact_trips_pickup_datetime;
DROP INDEX IF EXISTS idx_fact_trips_pickup_datetime_sk;
DROP INDEX IF EXISTS idx_fact_trips_dropoff_datetime_sk;
DROP INDEX IF EXISTS idx_fact_trips_pu_zone_sk;
DROP INDEX IF EXISTS idx_fact_trips_do_zone_sk;

ANALYZE fact_trips;

-- Run this query TWICE in pgAdmin and copy the 2nd run's Execution Time & Buffers
-- (2nd run ensures warm shared_buffers for a fair comparison):
EXPLAIN (ANALYZE, BUFFERS)
WITH rush_hour_trips AS (
    SELECT
        ft.trip_sk,
        ft.pickup_datetime,
        ft.pu_zone_sk,
        ft.do_zone_sk,
        ft.trip_distance,
        ft.total_amount
    FROM fact_trips AS ft
    WHERE ft.pickup_datetime >= TIMESTAMP '2025-11-12 08:00:00'
      AND ft.pickup_datetime < TIMESTAMP '2025-11-12 10:00:00'
      AND ft.pu_zone_sk = 74
)
SELECT
    pu.borough AS pickup_borough,
    pu.zone AS pickup_zone,
    dz.zone AS dropoff_zone,
    COUNT(*) AS trip_count,
    ROUND(AVG(r.trip_distance), 2) AS avg_distance,
    SUM(r.total_amount)::NUMERIC(12, 2) AS total_revenue
FROM rush_hour_trips AS r
INNER JOIN dim_zones AS pu
    ON r.pu_zone_sk = pu.zone_sk
INNER JOIN dim_zones AS dz
    ON r.do_zone_sk = dz.zone_sk
GROUP BY
    pu.borough,
    pu.zone,
    dz.zone
ORDER BY total_revenue DESC;


-- =============================================================================
-- STEP 2: Create B-Tree Indexes on Foreign Keys & Temporal Columns
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_fact_trips_pickup_datetime
    ON fact_trips (pickup_datetime);

CREATE INDEX IF NOT EXISTS idx_fact_trips_pickup_datetime_sk
    ON fact_trips (pickup_datetime_sk);

CREATE INDEX IF NOT EXISTS idx_fact_trips_dropoff_datetime_sk
    ON fact_trips (dropoff_datetime_sk);

CREATE INDEX IF NOT EXISTS idx_fact_trips_pu_zone_sk
    ON fact_trips (pu_zone_sk);

CREATE INDEX IF NOT EXISTS idx_fact_trips_do_zone_sk
    ON fact_trips (do_zone_sk);

-- Refresh planner statistics after index creation
ANALYZE fact_trips;


-- =============================================================================
-- STEP 3: Re-run the EXACT same query AFTER B-Tree Indexing
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
WITH rush_hour_trips AS (
    SELECT
        ft.trip_sk,
        ft.pickup_datetime,
        ft.pu_zone_sk,
        ft.do_zone_sk,
        ft.trip_distance,
        ft.total_amount
    FROM fact_trips AS ft
    WHERE ft.pickup_datetime >= TIMESTAMP '2025-11-12 08:00:00'
      AND ft.pickup_datetime < TIMESTAMP '2025-11-12 10:00:00'
      AND ft.pu_zone_sk = 74
)
SELECT
    pu.borough AS pickup_borough,
    pu.zone AS pickup_zone,
    dz.zone AS dropoff_zone,
    COUNT(*) AS trip_count,
    ROUND(AVG(r.trip_distance), 2) AS avg_distance,
    SUM(r.total_amount)::NUMERIC(12, 2) AS total_revenue
FROM rush_hour_trips AS r
INNER JOIN dim_zones AS pu
    ON r.pu_zone_sk = pu.zone_sk
INNER JOIN dim_zones AS dz
    ON r.do_zone_sk = dz.zone_sk
GROUP BY
    pu.borough,
    pu.zone,
    dz.zone
ORDER BY total_revenue DESC;