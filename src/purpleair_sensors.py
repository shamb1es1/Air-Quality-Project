import requests
import os
from dotenv import load_dotenv
import pandas as pd
import geopandas as gpd
from pathlib import Path
from api_utils import get_api_key, get_bounding_box


def get_sensors() -> pd.DataFrame:
    sensor_endpoint = 'https://api.purpleair.com/v1/sensors'

    # API header with the API key
    headers = {
        'X-API-Key': get_api_key('PurpleAir')
    }

    # Fields we want from the API
    required = {"sensor_index", "name", "latitude", "longitude", "date_created", "last_seen", "uptime"}

    # Get coordinates from api_utils
    NW_LAT, NW_LNG, SE_LAT, SE_LNG = get_bounding_box()

    # API parameters
    # Location type set to 0 to get capture outdoor sensors (this is pre-NJ filtering)
    parameters = {
        'fields': ",".join(required),
        'location_type': '0',
        'max_age': '0',
        'nwlng': NW_LNG,
        'nwlat': NW_LAT,
        'selng': SE_LNG,
        'selat': SE_LAT
    }

    # API call for sensors
    response = requests.get(sensor_endpoint, headers=headers, params=parameters).json()

    # Data validation and df creation
    fields = response.get("fields")
    rows = response.get("data")
    if not fields or rows is None:
        raise ValueError("Unexpected payload format: missing 'fields' or 'data'.")
    missing = required - set(fields)
    if missing:
        raise ValueError(f"Missing expected columns from API response: {missing}")
    data = pd.DataFrame(response['data'], columns=response['fields']).set_index('sensor_index')
    data.index.name = 'sensor_index'
    return data