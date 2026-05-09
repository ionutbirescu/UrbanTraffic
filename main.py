import requests
from fastapi import FastAPI
from sqlalchemy import create_engine, text
import os
from dotenv import load_dotenv

load_dotenv()

HERE_API_KEY = os.getenv("HERE_API_KEY")
DB_PASSWORD = os.getenv("DB_PASSWORD")

app = FastAPI()

# Database connection
DB_URL = f"postgresql://noiseadmin:{DB_PASSWORD}@noise-map-db.cwlgcckck9p9.us-east-1.rds.amazonaws.com:5432/noisemap"
engine = create_engine(DB_URL)

@app.get("/readings")
def get_readings():
    with engine.connect() as conn:
        result = conn.execute(text("SELECT * FROM readings ORDER BY recorded_at DESC LIMIT 100"))
        return [dict(row._mapping) for row in result]

@app.get("/heatmap")
def get_heatmap():
    with engine.connect() as conn:
        result = conn.execute(text("SELECT lat, lon, spl_db FROM readings"))
        return [{"lat": row.lat, "lon": row.lon, "intensity": row.spl_db} for row in result]

@app.get("/hotspots")
def get_hotspots():
    with engine.connect() as conn:
        result = conn.execute(text("SELECT * FROM readings WHERE spl_db > 70 ORDER BY recorded_at DESC"))
        return [dict(row._mapping) for row in result]
    
@app.get("/weather")
def get_weather(lat: float = 45.75, lon: float = 21.23):
    response = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,wind_speed_10m,relative_humidity_2m"
        }
    )
    data = response.json()
    current = data["current"]
    return {
        "lat": lat,
        "lon": lon,
        "temperature": current["temperature_2m"],
        "wind_speed": current["wind_speed_10m"],
        "humidity": current["relative_humidity_2m"],
        "fetched_at": current["time"]
    }

@app.get("/traffic")
def get_traffic(lat: float = 45.75, lon: float = 21.23):
    response = requests.get(
        "https://data.traffic.hereapi.com/v7/flow",
        params={
            "locationReferencing": "shape",
            "in": f"circle:{lat},{lon};r=500",
            "apiKey": HERE_API_KEY
        }
    )
    data = response.json()
    results = []
    for item in data.get("results", []):
        results.append({
            "road": item["location"]["description"],
            "speed": item["currentFlow"]["speed"],
            "jam_factor": item["currentFlow"]["jamFactor"],
            "traversability": item["currentFlow"]["traversability"]
        })
    return results

@app.get("/roadtype")
def get_road_type(lat: float = 45.75, lon: float = 21.23):
    query = f'[out:json];way(around:50,{lat},{lon})["highway"];out tags 1;'
    response = requests.get(
        "https://overpass-api.de/api/interpreter",
        params={"data": query},
        headers={"User-Agent": "noise-map-project/1.0"}
    )
    data = response.json()
    roads = []
    for element in data.get("elements", []):
        tags = element.get("tags", {})
        if "highway" in tags:
            roads.append({
                "name": tags.get("name", "unnamed"),
                "type": tags["highway"]
            })
    return roads