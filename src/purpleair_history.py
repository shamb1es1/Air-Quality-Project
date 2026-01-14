import requests
import os
from dotenv import load_dotenv
import pandas as pd
import geopandas as gpd
from pathlib import Path
import threading
import queue


# Return the PurpleAir API key from environment variables
def get_api_key() -> str:
    # Load environment variables (private PurpleAir API key) from .env file
    load_dotenv()
    key = os.getenv("PURPLEAIR_API_KEY")
    if not key:
        raise ValueError("PURPLEAIR_API_KEY not found in environment variables (.env).")
    return key

# Get the sensor indexes from the nj_sensors csv
def get_sensors(path: Path) -> pd.Series:
    sensors = pd.read_csv(path)
    return sensors['sensor_index']

# Get history of the sensor
def _get_history(sensor_id: int) -> pd.DataFrame:
    # API header with the API key
    headers = {
        'X-API-Key': get_api_key()
    }

    # API parameters
    parameters = {

    }

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
                df = _get_history(sensor_id)
                with good_lock:
                    good.append((df))
            except Exception as e:
                with bad_lock:
                    bad.append((sensor_id, str(e)))
            finally: 
                q.task_done()

    threads = []
    for _ in range(12):
        t = threading.Thread(target=catch_good_bad)
        t.start()
        threads.append(t)

    q.join()

    for _ in range(12):
        q.put(None)
    q.join()

    for t in threads:
        t.join()

    combined = pd.concat(good, ignore_index=True) if good else pd.DataFrame()
    return combined, bad


def main():
    # Make sure sensors csv path exists
    sensors_path = Path('data/nj_sensors.csv')
    if not sensors_path.exists():
        raise FileNotFoundError(f"{sensors_path} not found. Run get_nj_sensors first.")
    
    history_endpoint = "https://api.purpleair.com/v1/sensors/:sensor_index/history"

    # API header with the API key
    headers = {
        'X-API-Key': get_api_key()
    }

    # API parameters
    parameters = {

    }

    sensor_indexes = get_sensors(sensors_path)

    good, bad = call_histories(sensor_indexes)



if __name__ == "__main__":
    main()