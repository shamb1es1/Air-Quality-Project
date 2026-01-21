import os
from dotenv import load_dotenv


# Keys to be passed to get different env API keys
key_names = {
    "PurpleAir": "PURPLEAIR_API_KEY",
    "AirNow": "AIRNOW_API_KEY"
}

# Arbitrary "bounding box" coordinates for New Jersey
NW_LAT, NW_LNG = 41.357633, -75.560315
SE_LAT, SE_LNG = 38.928212, -73.894883

def get_bounding_box() -> tuple:
    return NW_LAT, NW_LNG, SE_LAT, SE_LNG


# Return the PurpleAir API key from environment variables
def get_api_key(key_name: str) -> str:
    # Load environment variables (private PurpleAir API key) from .env file
    load_dotenv()
    key = os.getenv(key_names[key_name])
    if not key:
        raise ValueError(f"{key_name} API key not found in environment variables. Add it to a .env file.")
    return key