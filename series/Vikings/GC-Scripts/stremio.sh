#!/bin/bash

# ==============================================================================
# Script Name: stremio.sh
# Description: Generates M3U playlists with Landscape Posters for Movies & TV
#              Optimized for Google Colab.
# ==============================================================================

# 1. Install Dependencies
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║               🚀 Initializing Stremio M3U Generator                ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
pip install -q requests

# 2. Generate Python Logic
cat << 'EOF' > m3u_core.py
import requests
import time
import re
import sys
import os
import json
from typing import List, Dict, Optional, Any

# --- CONFIGURATION ---
CONFIG = {
    "STREMIO_BASE_URL": "https://stremio--stremio--m72vl4mnxzkd.code.run",
    "TMDB_API_KEY": "f320fa5c189058be63b5420c044f64e1",
    "DB_INDEX": "1",
    "TIMEOUT": 10
}

class APIClient:
    """Handles HTTP requests with auto-retry."""
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})

    def fetch(self, url: str, params: Optional[Dict] = None) -> Optional[Dict]:
        try:
            response = self.session.get(url, params=params, timeout=CONFIG["TIMEOUT"])
            if response.status_code == 404: return None
            response.raise_for_status()
            return response.json()
        except:
            return None

class MediaService:
    def __init__(self):
        self.client = APIClient()

    def search_tmdb(self, query: str) -> List[Dict[str, Any]]:
        """Searches TMDB and grabs the Landscape Backdrop for movies."""
        url = "https://api.themoviedb.org/3/search/multi"
        params = {
            "api_key": CONFIG["TMDB_API_KEY"],
            "query": query,
            "include_adult": "false",
            "language": "en-US" # Force English
        }
        data = self.client.fetch(url, params)
        if not data: return []

        results = []
        for item in data.get("results", []):
            if item.get("media_type") not in ["movie", "tv"]:
                continue
            
            title = item.get("title") or item.get("name")
            date = item.get("release_date") or item.get("first_air_date") or "N/A"
            
            # --- FETCH LANDSCAPE POSTER (BACKDROP) ---
            backdrop_path = item.get("backdrop_path")
            poster_url = f"https://image.tmdb.org/t/p/original{backdrop_path}" if backdrop_path else ""

            results.append({
                "id": item["id"],
                "type": item["media_type"],
                "title": title,
                "year": date[:4],
                "poster": poster_url  # Store the image URL here
            })
        return results

    def get_tv_details(self, tmdb_id: int) -> Dict:
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}"
        return self.client.fetch(url, {"api_key": CONFIG["TMDB_API_KEY"]}) or {}

    def get_season_episodes(self, tmdb_id: int, season_number: int) -> List[Dict]:
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}/season/{season_number}"
        data = self.client.fetch(url, {"api_key": CONFIG["TMDB_API_KEY"]})
        return data.get("episodes", []) if data else []

    def get_stream_url(self, tmdb_id: int, season=None, episode=None) -> List[Dict]:
        if season is not None:
            stream_id = f"{tmdb_id}-{CONFIG['DB_INDEX']}:{season}:{episode}"
            endpoint = "series"
        else:
            stream_id = f"{tmdb_id}-{CONFIG['DB_INDEX']}"
            endpoint = "movie"

        url = f"{CONFIG['STREMIO_BASE_URL']}/stremio/stream/{endpoint}/{stream_id}.json"
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                return response.json().get("streams", [])
        except:
            pass
        return []

class M3UGenerator:
    def __init__(self):
        self.service = MediaService()
        self.playlists = {"1080p": ["#EXTM3U"], "720p": ["#EXTM3U"], "480p": ["#EXTM3U"]}

    def add_entry(self, title: str, streams: List[Dict], thumb: str):
        added = set()
        for s in streams:
            meta = (s.get("name", "") + " " + s.get("title", "")).lower()
            url = s.get("url")
            if not url: continue

            # Create M3U Entry with Landscape Poster (tvg-logo)
            # Format: #EXTINF:-1 group-title="Category" tvg-logo="URL", Title
            entry = f'#EXTINF:-1 tvg-logo="{thumb}",{title}\n{url}'
            
            if "1080" in meta and "1080p" not in added:
                self.playlists["1080p"].append(entry)
                added.add("1080p")
            elif "720" in meta and "720p" not in added:
                self.playlists["720p"].append(entry)
                added.add("720p")
            elif "480" in meta and "480p" not in added:
                self.playlists["480p"].append(entry)
                added.add("480p")
        
        if added:
            print(f"✅ Added: {title}")

    def process_selection(self, media: Dict):
        print(f"\n🚀 Extraction Started: {media['title']} ({media['year']})")
        print("-" * 60)

        if media["type"] == "movie":
            streams = self.service.get_stream_url(media["id"])
            if streams:
                # Use the Landscape Poster we fetched in search
                self.add_entry(media["title"], streams, media["poster"])
            else:
                print("❌ No streams found for this movie.")

        elif media["type"] == "tv":
            details = self.service.get_tv_details(media["id"])
            seasons = details.get("number_of_seasons", 0)

            for s in range(1, seasons + 1):
                print(f"📂 Scanning Season {s}...")
                episodes = self.service.get_season_episodes(media["id"], s)
                for ep in episodes:
                    s_num, e_num = ep["season_number"], ep["episode_number"]
                    ep_title = f"{media['title']} S{s_num:02d}E{e_num:02d} - {ep['name']}"
                    
                    # Episode Landscape Thumbnail
                    thumb = f"https://image.tmdb.org/t/p/original{ep['still_path']}" if ep.get("still_path") else ""
                    
                    streams = self.service.get_stream_url(media["id"], s_num, e_num)
                    if streams:
                        self.add_entry(ep_title, streams, thumb)
                    time.sleep(0.05)

    def save_playlists(self, base_name: str):
        safe_name = re.sub(r'[\\/*?:"<>|]', "", base_name).replace(" ", "_")
        saved = False
        print("\n" + "-" * 60)
        for quality, content in self.playlists.items():
            if len(content) > 1:
                filename = f"{safe_name}_{quality}.m3u"
                with open(filename, "w", encoding="utf-8") as f:
                    f.write("\n".join(content))
                print(f"💾 Generated: {filename}")
                saved = True
        
        if not saved:
            print("⚠️ No valid streams found. No files created.")

def main():
    try:
        gen = M3UGenerator()
        print("\n🔎 TMDB Search")
        query = input("👉 Enter Name: ").strip()
        if not query: return

        results = gen.service.search_tmdb(query)
        if not results:
            print("❌ No results.")
            return

        print(f"\n📺 Results:")
        for idx, item in enumerate(results):
            print(f"   {idx + 1}. {item['title']} ({item['year']}) [{item['type'].upper()}]")

        choice = int(input("\n🔢 Select: ")) - 1
        if choice < 0 or choice >= len(results): raise ValueError

        selected = results[choice]
        gen.process_selection(selected)
        gen.save_playlists(selected['title'])

    except Exception as e:
        print(f"\n❌ Error: {e}")

if __name__ == "__main__":
    main()
EOF

# 3. Run Logic
python3 m3u_core.py
