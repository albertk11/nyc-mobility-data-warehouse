-- =============================================================================
-- 01_staging_deduplication.sql
-- Purpose: Clean raw NYC Green Taxi & Taxi Zones data, enforce types,
--          handle NULLs, generate deterministic MD5 Surrogate Keys,
--          and deduplicate records at trip grain.
-- =============================================================================

-- 1. Staging Taxi Zones Lookup
DROP TABLE IF EXISTS stg_taxi_zones CASCADE;

CREATE TABLE stg_taxi_zones AS
WITH cleaned_zones AS (
    SELECT
        locationid::INTEGER AS location_id,
        COALESCE(NULLIF(TRIM(borough), ''), 'Unknown') AS borough,
        COALESCE(NULLIF(TRIM(zone), ''), 'Unknown') AS zone,
        COALESCE(NULLIF(TRIM(service_zone), ''), 'Unknown') AS service_zone
    FROM taxi_zones
    WHERE locationid IS NOT NULL
)
SELECT
    location_id,
    borough,
    zone,
    service_zone
FROM cleaned_zones;

ALTER TABLE stg_taxi_zones
    ADD PRIMARY KEY (location_id);


-- 2. Staging Green Taxi Trips (Cleaned & Deduplicated)
DROP TABLE IF EXISTS stg_green_taxi_trips CASCADE;

CREATE TABLE stg_green_taxi_trips AS
WITH cleaned_trips AS (
    SELECT
        COALESCE(vendorid, -1)::INTEGER AS vendor_id,
        lpep_pickup_datetime::TIMESTAMP AS pickup_datetime,
        lpep_dropoff_datetime::TIMESTAMP AS dropoff_datetime,
        COALESCE(NULLIF(UPPER(TRIM(store_and_fwd_flag)), ''), 'N')::VARCHAR(1) AS store_and_fwd_flag,
        COALESCE(ratecodeid, 99)::INTEGER AS rate_code_id,
        pulocationid::INTEGER AS pu_location_id,
        dolocationid::INTEGER AS do_location_id,
        COALESCE(passenger_count, 0)::INTEGER AS passenger_count,
        trip_distance::NUMERIC(10, 2) AS trip_distance,
        fare_amount::NUMERIC(10, 2) AS fare_amount,
        COALESCE(extra, 0)::NUMERIC(10, 2) AS extra,
        COALESCE(mta_tax, 0)::NUMERIC(10, 2) AS mta_tax,
        COALESCE(tip_amount, 0)::NUMERIC(10, 2) AS tip_amount,
        COALESCE(tolls_amount, 0)::NUMERIC(10, 2) AS tolls_amount,
        COALESCE(ehail_fee, 0)::NUMERIC(10, 2) AS ehail_fee,
        COALESCE(improvement_surcharge, 0)::NUMERIC(10, 2) AS improvement_surcharge,
        total_amount::NUMERIC(10, 2) AS total_amount,
        COALESCE(payment_type, 5)::INTEGER AS payment_type,
        COALESCE(trip_type, 0)::INTEGER AS trip_type,
        COALESCE(congestion_surcharge, 0)::NUMERIC(10, 2) AS congestion_surcharge,
        COALESCE(cbd_congestion_fee, 0)::NUMERIC(10, 2) AS cbd_congestion_fee
    FROM green_taxi_trips
    WHERE lpep_pickup_datetime >= TIMESTAMP '2025-11-01 00:00:00'
      AND lpep_pickup_datetime < TIMESTAMP '2025-12-01 00:00:00'
      AND lpep_dropoff_datetime >= lpep_pickup_datetime
      AND trip_distance > 0
      AND fare_amount > 0
      AND total_amount > 0
      AND pulocationid IS NOT NULL
      AND dolocationid IS NOT NULL
),
deduplicated_trips AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                vendor_id,
                pickup_datetime,
                dropoff_datetime,
                pu_location_id,
                do_location_id
            ORDER BY
                total_amount DESC,
                trip_distance DESC
        ) AS row_num
    FROM cleaned_trips
)
SELECT
    MD5(
        CONCAT_WS(
            '|',
            vendor_id,
            pickup_datetime,
            dropoff_datetime,
            pu_location_id,
            do_location_id
        )
    ) AS trip_sk,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    store_and_fwd_flag,
    rate_code_id,
    pu_location_id,
    do_location_id,
    passenger_count,
    trip_distance,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    ehail_fee,
    improvement_surcharge,
    total_amount,
    payment_type,
    trip_type,
    congestion_surcharge,
    cbd_congestion_fee
FROM deduplicated_trips
WHERE row_num = 1;

ALTER TABLE stg_green_taxi_trips
    ADD PRIMARY KEY (trip_sk);