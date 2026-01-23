import requests
import os
from dotenv import load_dotenv
import pandas as pd
import geopandas as gpd
from pathlib import Path
import threading
import queue
import datetime
import time
from api_utils import get_api_key


# Get the sensor indexes from the purpleair_sensors csv
def get_sensor_indexes(path: Path) -> pd.Series:
    sensors = pd.read_csv(path)
    return sensors['sensor_index']

# Get history of the sensor
def get_history(sensor_id: int) -> pd.DataFrame:

    # Days in 2025
    beginning = datetime.datetime(2025, 1, 1, 0, 0, 0, tzinfo=datetime.timezone.utc)
    end = datetime.datetime(2026, 1, 1, 0, 0, 0, tzinfo=datetime.timezone.utc)

    # Fields we want from the API
    required = ["pm2.5_atm_a", "pm2.5_atm_b","pm2.5_cf_1_a", "pm2.5_cf_1_b", "humidity", "temperature"]

    # API header with the API key
    headers = {
        'X-API-Key': get_api_key('PurpleAir')
    }

    chunks = []
    chunk_beginning = beginning
    while chunk_beginning < end:
        # See if we need another full 180 days of data or we have leftover days
        chunk_end = min(chunk_beginning + datetime.timedelta(days=180), end)

        # API parameters
        parameters = {
            'fields': ",".join(required),
            "start_timestamp": int(chunk_beginning.timestamp()),
            "end_timestamp": int(chunk_end.timestamp()),
            "average": 60
        }
    
        response = requests.get(url=f'https://api.purpleair.com/v1/sensors/{sensor_id}/history',headers=headers,params=parameters)
        response.raise_for_status()
        response = response.json()

        # Data validation and df creation
        fields = response.get("fields")
        rows = response.get("data", [])
        
        if not isinstance(fields, list):
            raise ValueError(f"Unexpected payload format: 'fields' missing or not a list for sensor {sensor_id}")
        if rows is None:
            raise ValueError(f"Unexpected payload format: 'data' is None for sensor {sensor_id}")

        
        missing = set(required) - set(fields)
        if missing:
            raise ValueError(f"Missing expected columns from API response: {missing}")
        
        # Create df and create column with sensor_id if not implicitly retrieved with API response
        df_chunk = pd.DataFrame(rows, columns=fields)
        df_chunk["sensor_index"] = sensor_id
        chunks.append(df_chunk)

        chunk_beginning = chunk_end

        time.sleep(2)

    # In case chunks doesn't get populated
    if not chunks: return pd.DataFrame()

    # Return 
    non_empty = [df for df in chunks if not df.empty]
    if not non_empty:
        return pd.DataFrame()
    return pd.concat(non_empty, ignore_index=True)


def call_histories(sensors: pd.Series):

    q = queue.Queue()
    good = []
    bad = []

    for sensor_id in sensors:
        q.put(sensor_id)

    good_lock = threading.Lock()
    bad_lock = threading.Lock()

    def catch_good_bad():
        while True:
            sensor_id = q.get()
            if sensor_id is None:
                q.task_done()
                return
            try:
                df = get_history(sensor_id)
                with good_lock:
                    good.append((df))
                    print(f"{sensor_id}: success, {len(df)} rows")
            except Exception as e:
                with bad_lock:
                    bad.append((sensor_id, str(e)))
            finally: 
                q.task_done()

    threads = []
    for _ in range(6):
        t = threading.Thread(target=catch_good_bad)
        t.start()
        threads.append(t)

    q.join()

    for _ in range(6):
        q.put(None)
    q.join()

    for t in threads:
        t.join()

    combined = pd.concat(good, ignore_index=True) if good else pd.DataFrame()
    return combined, bad