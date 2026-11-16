-- =============================================================================
-- 03_build_star_schema.sql
-- Purpose: Build a Kimball-style Star Schema (dim_datetime, dim_zones, fact_trips)
--          with Surrogate Keys, Role-Playing Dimensions, and Referential Integrity.
-- =============================================================================

-- Drop Fact first due to Foreign Key dependencies (Idempotency)
DROP TABLE IF EXISTS fact_trips CASCADE;
DROP TABLE IF EXISTS dim_datetime CASCADE;
DROP TABLE IF EXISTS dim_zones CASCADE;


-- 1. Dimension: dim_datetime (Hourly grain generated dynamically via generate_series)
CREATE TABLE dim_datetime (
    datetime_sk INTEGER PRIMARY KEY,
    full_datetime TIMESTAMP NOT NULL UNIQUE,
    date_actual DATE NOT NULL,
    year_number INTEGER NOT NULL,
    month_number INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    hour_of_day INTEGER NOT NULL,
    day_of_week_iso INTEGER NOT NULL,
    day_name VARCHAR(10) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_rush_hour BOOLEAN NOT NULL
);

INSERT INTO dim_datetime (
    datetime_sk,
    full_datetime,
    date_actual,
    year_number,
    month_number,
    day_of_month,
    hour_of_day,
    day_of_week_iso,
    day_name,
    is_weekend,
    is_rush_hour
)
WITH time_bounds AS (
    SELECT
        DATE_TRUNC('hour', MIN(pickup_datetime)) AS min_hour,
        DATE_TRUNC('hour', MAX(dropoff_datetime)) AS max_hour
    FROM stg_green_taxi_trips
),
hour_series AS (
    SELECT
        GENERATE_SERIES(
            tb.min_hour,
            tb.max_hour,
            INTERVAL '1 hour'
        ) AS full_datetime
    FROM time_bounds AS tb
)
SELECT
    TO_CHAR(full_datetime, 'YYYYMMDDHH24')::INTEGER AS datetime_sk,
    full_datetime,
    full_datetime::DATE AS date_actual,
    EXTRACT(YEAR FROM full_datetime)::INTEGER AS year_number,
    EXTRACT(MONTH FROM full_datetime)::INTEGER AS month_number,
    EXTRACT(DAY FROM full_datetime)::INTEGER AS day_of_month,
    EXTRACT(HOUR FROM full_datetime)::INTEGER AS hour_of_day,
    EXTRACT(ISODOW FROM full_datetime)::INTEGER AS day_of_week_iso,
    TRIM(TO_CHAR(full_datetime, 'Day')) AS day_name,
    EXTRACT(ISODOW FROM full_datetime) IN (6, 7) AS is_weekend,
    (
        EXTRACT(ISODOW FROM full_datetime) BETWEEN 1 AND 5
        AND (
            EXTRACT(HOUR FROM full_datetime) BETWEEN 7 AND 9
            OR EXTRACT(HOUR FROM full_datetime) BETWEEN 16 AND 19
        )
    ) AS is_rush_hour
FROM hour_series
ORDER BY full_datetime;


-- 2. Dimension: dim_zones (Surrogate Key decoupled from Business Key location_id)
CREATE TABLE dim_zones (
    zone_sk INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_id INTEGER NOT NULL,
    borough VARCHAR(50) NOT NULL,
    zone VARCHAR(100) NOT NULL,
    service_zone VARCHAR(50) NOT NULL
);

INSERT INTO dim_zones (
    location_id,
    borough,
    zone,
    service_zone
)
SELECT
    location_id,
    borough,
    zone,
    service_zone
FROM stg_taxi_zones
ORDER BY location_id;


-- 3. Fact Table: fact_trips (Grain: one deduplicated Green Taxi trip)
CREATE TABLE fact_trips (
    trip_sk VARCHAR(32) PRIMARY KEY,
    pickup_datetime_sk INTEGER NOT NULL REFERENCES dim_datetime (datetime_sk),
    dropoff_datetime_sk INTEGER NOT NULL REFERENCES dim_datetime (datetime_sk),
    pu_zone_sk INTEGER NOT NULL REFERENCES dim_zones (zone_sk),
    do_zone_sk INTEGER NOT NULL REFERENCES dim_zones (zone_sk),
    vendor_id INTEGER NOT NULL,
    rate_code_id INTEGER NOT NULL,
    payment_type INTEGER NOT NULL,
    trip_type INTEGER NOT NULL,
    store_and_fwd_flag VARCHAR(1) NOT NULL,
    pickup_datetime TIMESTAMP NOT NULL,
    dropoff_datetime TIMESTAMP NOT NULL,
    passenger_count INTEGER NOT NULL,
    trip_distance NUMERIC(10, 2) NOT NULL,
    trip_duration_minutes NUMERIC(10, 2) NOT NULL,
    fare_amount NUMERIC(10, 2) NOT NULL,
    extra NUMERIC(10, 2) NOT NULL,
    mta_tax NUMERIC(10, 2) NOT NULL,
    tip_amount NUMERIC(10, 2) NOT NULL,
    tolls_amount NUMERIC(10, 2) NOT NULL,
    ehail_fee NUMERIC(10, 2) NOT NULL,
    improvement_surcharge NUMERIC(10, 2) NOT NULL,
    congestion_surcharge NUMERIC(10, 2) NOT NULL,
    cbd_congestion_fee NUMERIC(10, 2) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL
);

INSERT INTO fact_trips (
    trip_sk,
    pickup_datetime_sk,
    dropoff_datetime_sk,
    pu_zone_sk,
    do_zone_sk,
    vendor_id,
    rate_code_id,
    payment_type,
    trip_type,
    store_and_fwd_flag,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance,
    trip_duration_minutes,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    ehail_fee,
    improvement_surcharge,
    congestion_surcharge,
    cbd_congestion_fee,
    total_amount
)
WITH staged_with_keys AS (
    SELECT
        t.trip_sk,
        TO_CHAR(DATE_TRUNC('hour', t.pickup_datetime), 'YYYYMMDDHH24')::INTEGER AS pickup_datetime_sk,
        TO_CHAR(DATE_TRUNC('hour', t.dropoff_datetime), 'YYYYMMDDHH24')::INTEGER AS dropoff_datetime_sk,
        pu_z.zone_sk AS pu_zone_sk,
        do_z.zone_sk AS do_zone_sk,
        t.vendor_id,
        t.rate_code_id,
        t.payment_type,
        t.trip_type,
        t.store_and_fwd_flag,
        t.pickup_datetime,
        t.dropoff_datetime,
        t.passenger_count,
        t.trip_distance,
        ROUND(
            (EXTRACT(EPOCH FROM (t.dropoff_datetime - t.pickup_datetime)) / 60.0)::NUMERIC,
            2
        ) AS trip_duration_minutes,
        t.fare_amount,
        t.extra,
        t.mta_tax,
        t.tip_amount,
        t.tolls_amount,
        t.ehail_fee,
        t.improvement_surcharge,
        t.congestion_surcharge,
        t.cbd_congestion_fee,
        t.total_amount
    FROM stg_green_taxi_trips AS t
    INNER JOIN dim_zones AS pu_z
        ON t.pu_location_id = pu_z.location_id
    INNER JOIN dim_zones AS do_z
        ON t.do_location_id = do_z.location_id
)
SELECT *
FROM staged_with_keys;