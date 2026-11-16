-- =============================================================================
-- 02_time_series_analytics.sql
-- Purpose: OLAP time-series analysis on staged NYC Green Taxi trips:
--          - Day-over-Day (DoD %) growth with LAG() and LEAD()
--          - 7-day moving averages using a continuous Date Spine & Window Frame
--          - Top-3 pickup zones per borough using DENSE_RANK()
-- =============================================================================

-- 1. Daily Time-Series OLAP View (LAG, LEAD, DoD %, 7-Day Moving Average)
CREATE OR REPLACE VIEW vw_daily_time_series_olap AS
WITH date_spine AS (
    SELECT gs::DATE AS trip_date
    FROM generate_series(
        DATE '2025-11-01',
        DATE '2025-11-30',
        INTERVAL '1 day'
    ) AS gs
),
daily_aggregates AS (
    SELECT
        pickup_datetime::DATE AS trip_date,
        COUNT(*) AS total_trips,
        SUM(total_amount)::NUMERIC(12, 2) AS total_revenue,
        ROUND(AVG(trip_distance), 2) AS avg_trip_distance,
        ROUND(AVG(total_amount), 2) AS avg_trip_revenue
    FROM stg_green_taxi_trips
    GROUP BY pickup_datetime::DATE
),
daily_series AS (
    SELECT
        ds.trip_date,
        COALESCE(da.total_trips, 0) AS total_trips,
        COALESCE(da.total_revenue, 0.00)::NUMERIC(12, 2) AS total_revenue,
        COALESCE(da.avg_trip_distance, 0.00)::NUMERIC(10, 2) AS avg_trip_distance,
        COALESCE(da.avg_trip_revenue, 0.00)::NUMERIC(10, 2) AS avg_trip_revenue
    FROM date_spine AS ds
    LEFT JOIN daily_aggregates AS da
        ON ds.trip_date = da.trip_date
),
window_metrics AS (
    SELECT
        trip_date,
        total_trips,
        LAG(total_trips, 1) OVER (ORDER BY trip_date) AS prev_day_trips,
        LEAD(total_trips, 1) OVER (ORDER BY trip_date) AS next_day_trips,
        total_revenue,
        LAG(total_revenue, 1) OVER (ORDER BY trip_date) AS prev_day_revenue,
        LEAD(total_revenue, 1) OVER (ORDER BY trip_date) AS next_day_revenue,
        ROUND(
            AVG(total_trips) OVER (
                ORDER BY trip_date
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ),
            2
        ) AS ma_7d_trips,
        ROUND(
            AVG(total_revenue) OVER (
                ORDER BY trip_date
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ),
            2
        ) AS ma_7d_revenue,
        avg_trip_distance,
        avg_trip_revenue
    FROM daily_series
)
SELECT
    trip_date,
    TO_CHAR(trip_date, 'Dy') AS day_of_week,
    total_trips,
    prev_day_trips,
    next_day_trips,
    ROUND(
        ((total_trips - prev_day_trips)::NUMERIC / NULLIF(prev_day_trips, 0)) * 100,
        2
    ) AS dod_trips_pct,
    total_revenue,
    prev_day_revenue,
    next_day_revenue,
    ROUND(
        ((total_revenue - prev_day_revenue) / NULLIF(prev_day_revenue, 0)) * 100,
        2
    ) AS dod_revenue_pct,
    ma_7d_trips,
    ma_7d_revenue,
    avg_trip_distance,
    avg_trip_revenue
FROM window_metrics
ORDER BY trip_date;


-- 2. Top-3 Pickup Zones per Borough View (DENSE_RANK + Revenue Share)
CREATE OR REPLACE VIEW vw_borough_top_zones_olap AS
WITH zone_metrics AS (
    SELECT
        COALESCE(z.borough, 'Unknown') AS borough,
        COALESCE(z.zone, 'Unknown') AS pickup_zone,
        COUNT(*) AS total_trips,
        SUM(t.total_amount)::NUMERIC(12, 2) AS total_revenue,
        ROUND(AVG(t.trip_distance), 2) AS avg_trip_distance,
        ROUND(AVG(t.tip_amount), 2) AS avg_tip_amount
    FROM stg_green_taxi_trips AS t
    LEFT JOIN stg_taxi_zones AS z
        ON t.pu_location_id = z.location_id
    GROUP BY
        COALESCE(z.borough, 'Unknown'),
        COALESCE(z.zone, 'Unknown')
),
ranked_zones AS (
    SELECT
        borough,
        pickup_zone,
        total_trips,
        total_revenue,
        avg_trip_distance,
        avg_tip_amount,
        SUM(total_revenue) OVER (PARTITION BY borough) AS borough_total_revenue,
        DENSE_RANK() OVER (
            PARTITION BY borough
            ORDER BY total_revenue DESC, total_trips DESC
        ) AS borough_rank
    FROM zone_metrics
)
SELECT
    borough,
    borough_rank,
    pickup_zone,
    total_trips,
    total_revenue,
    ROUND(
        (total_revenue / NULLIF(borough_total_revenue, 0)) * 100,
        2
    ) AS borough_revenue_share_pct,
    avg_trip_distance,
    avg_tip_amount
FROM ranked_zones
WHERE borough_rank <= 3
ORDER BY borough, borough_rank;