from datetime import datetime, timedelta, timezone
from pathlib import Path
from api_utils import get_api_key, get_bounding_box
import pandas as pd
import geo_utils
import requests

endpoint = 'https://www.airnowapi.org/aq/data/'

key = get_api_key("AirNow")

# Get coordinates from api_utils
NW_LAT, NW_LNG, SE_LAT, SE_LNG = get_bounding_box()

params = {
    'bbox': f"{NW_LNG},{SE_LAT},{SE_LNG},{NW_LAT}",
    'startdate': '',
    'enddate': '',
    'parameters': 'pm25',
    'datatype': 'B',
    'format': 'application/json',
    'api_key': key,
    'verbose': 1,
    'includerawconcentrations': 1
}

def get_airnow_history() -> pd.DataFrame:
    # Make sure data directory exists
    Path("data").mkdir(parents=True, exist_ok=True)
    out_path = Path("data/airnow_data_filtered.csv")
    if out_path.exists():
        out_path.unlink()

    # Loop through 7-day chunks in 2025 and append to csv
    start = datetime(2025, 1, 1, tzinfo=timezone.utc)
    end = datetime(2025, 12, 31, tzinfo=timezone.utc)
    all_chunks = []
    chunk_beginning = start
    while chunk_beginning < end:
        chunk_end = min(chunk_beginning + timedelta(days=7), end)
        params["startdate"] = chunk_beginning.strftime("%Y-%m-%dT%H")
        params["enddate"]   = chunk_end.strftime("%Y-%m-%dT%H")
        resp = requests.get(endpoint, params=params, timeout=30)
        resp.raise_for_status()
        chunk = pd.DataFrame(resp.json())
        if not chunk.empty:
            chunk.columns = chunk.columns.str.lower()
            chunk = geo_utils.filter_non_nj(chunk)
            all_chunks.append(chunk)
        chunk_beginning = chunk_end

    if not all_chunks:
        return pd.DataFrame()
    
    return pd.concat(all_chunks, ignore_index=True)