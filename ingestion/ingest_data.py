import argparse
import os
import time
import requests
import pandas as pd
import pyarrow.parquet as pq
from sqlalchemy import create_engine
from sqlalchemy.engine import URL


def download_file(url: str, local_path: str) -> None:
    print(f"Downloading {url}...")
    response = requests.get(url, stream=True, timeout=60)
    response.raise_for_status()
    with open(local_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)
    print(f"Saved to {local_path}")


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df.columns = df.columns.str.strip().str.lower()
    return df


def ingest_parquet_in_chunks(file_path: str, table_name: str, engine, batch_size: int = 100_000) -> None:
    parquet_file = pq.ParquetFile(file_path)
    total_rows = 0
    first_chunk = True

    for batch in parquet_file.iter_batches(batch_size=batch_size):
        t_start = time.time()
        df = normalize_columns(batch.to_pandas())

        if first_chunk:
            df.head(0).to_sql(name=table_name, con=engine, if_exists="replace", index=False)
            first_chunk = False

        df.to_sql(name=table_name, con=engine, if_exists="append", index=False, chunksize=10_000)
        total_rows += len(df)
        print(f"[{table_name}] Inserted {len(df)} rows (Total: {total_rows}) in {time.time() - t_start:.2f}s")


def ingest_csv(file_path: str, table_name: str, engine) -> None:
    t_start = time.time()
    df = normalize_columns(pd.read_csv(file_path))
    df.to_sql(name=table_name, con=engine, if_exists="replace", index=False, chunksize=10_000)
    print(f"[{table_name}] Inserted {len(df)} rows in {time.time() - t_start:.2f}s")


def main(params):
    connection_url = URL.create(
        drivername="postgresql+psycopg",
        username=params.user,
        password=params.password,
        host=params.host,
        port=int(params.port),
        database=params.db,
    )
    engine = create_engine(connection_url)

    trips_path = "/tmp/green_trips.parquet"
    zones_path = "/tmp/taxi_zone_lookup.csv"

    try:
        download_file(params.trips_url, trips_path)
        ingest_parquet_in_chunks(trips_path, params.trips_table, engine)

        download_file(params.zones_url, zones_path)
        ingest_csv(zones_path, params.zones_table, engine)

        print("Ingestion completed successfully!")
    finally:
        engine.dispose()
        for path in (trips_path, zones_path):
            if os.path.exists(path):
                os.remove(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest NYC Mobility data into PostgreSQL")
    parser.add_argument("--user", default=os.getenv("POSTGRES_USER", "root"))
    parser.add_argument("--password", default=os.getenv("POSTGRES_PASSWORD", "root"))
    parser.add_argument("--host", default=os.getenv("POSTGRES_HOST", "db"))
    parser.add_argument("--port", default=os.getenv("POSTGRES_PORT", "5432"))
    parser.add_argument("--db", default=os.getenv("POSTGRES_DB", "nyc_mobility"))
    parser.add_argument("--trips_table", default="green_taxi_trips")
    parser.add_argument("--zones_table", default="taxi_zones")
    parser.add_argument(
        "--trips_url",
        default="https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2025-11.parquet",
    )
    parser.add_argument(
        "--zones_url",
        default="https://github.com/DataTalksClub/nyc-tlc-data/releases/download/misc/taxi_zone_lookup.csv",
    )

    args = parser.parse_args()
    main(args)