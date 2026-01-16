import requests
import os
from dotenv import load_dotenv
import pandas as pd
import geopandas as gpd
from pathlib import Path


# Arbitrary "bounding box" coordinates for New Jersey
NW_LAT, NW_LNG = 41.357633, -75.560315
SE_LAT, SE_LNG = 38.928212, -73.894883


# Return the PurpleAir API key from environment variables
def get_api_key() -> str:
    # Load environment variables (private PurpleAir API key) from .env file
    load_dotenv()
    key = os.getenv('PURPLEAIR_API_KEY')
    if not key:
        raise ValueError("PurpleAir API key not found in environment variables. Add it to a .env file.")
    return key


def get_sensors() -> pd.DataFrame:
    sensor_endpoint = 'https://api.purpleair.com/v1/sensors'

    # API header with the API key
    headers = {
        'X-API-Key': get_api_key()
    }

    # Fields we want from the API
    required = {"sensor_index", "name", "latitude", "longitude", "date_created", "last_seen", "uptime"}

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


def filter_non_nj(sensors: pd.DataFrame) -> pd.DataFrame:
    nj_path = Path("data/nj_coordinates/cb_2024_34_sldu_500k.shp")
    nj = gpd.read_file(nj_path).to_crs("EPSG:4326")
    gdf = gpd.GeoDataFrame( 
        sensors.copy(),
        geometry=gpd.points_from_xy(sensors["longitude"], sensors["latitude"]),
        crs="EPSG:4326"
    )
    nj_sensors = gpd.sjoin(gdf, nj, how="inner", predicate="within")
    out = nj_sensors.loc[:, sensors.columns].copy().sort_index()
    return pd.DataFrame(out)


def main():
    sensors_df = get_sensors()
    nj_sensors = filter_non_nj(sensors_df)
    nj_sensors.to_csv("data/nj_sensors.csv")


if __name__ == "__main__":
    main()