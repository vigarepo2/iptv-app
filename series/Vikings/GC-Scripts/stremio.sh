#!/bin/bash

# ==============================================================================
# Script Name: stremio.sh
# Description: Automates the generation of M3U playlists from Stremio Backend
#              using TMDB metadata. Optimized for Google Colab environments.
# Author:      VigaRepo (Refactored)
# ==============================================================================

# 1. Environment Setup & Dependency Installation
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║               🚀 Initializing Stremio M3U Generator                ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "[INFO] Installing required Python dependencies..."
pip install -q requests

# 2. Generate the Python Application
# We use a Here-Document (EOF) to embed the Python code into this shell script.
cat << 'EOF' > m3u_core.py
"""
M3U Generator Core Module
-------------------------
A professional-grade script to bridge TMDB metadata with Stremio backend streams
and generate standardized M3U playlists.
"""

import requests
import time
import re
import sys
import os
import json
from typing import List, Dict, Optional, Any, Tuple

# --- CONFIGURATION CONSTANTS ---
CONFIG = {
    "STREMIO_BASE_URL": "https://stremio--stremio--m72vl4mnxzkd.code.run",
    "TMDB_API_KEY": "f320fa5c189058be63b5420c044f64e1",
    "DB_INDEX": "1",  # MongoDB shard index
    "TIMEOUT": 10,    # Request timeout in seconds
    "MAX_RETRIES": 3, # Max API retries
    "RETRY_DELAY": 1  # Seconds between retries
}

# --- UTILITY CLASS ---
class Logger:
    """Handles console output with standardized formatting."""
    
    @staticmethod
    def info(msg: str):
        print(f"ℹ️  [INFO] {msg}")

    @staticmethod
    def success(msg: str):
        print(f"✅ [SUCCESS] {msg}")

    @staticmethod
    def warning(msg: str):
        print(f"⚠️  [WARN] {msg}")

    @staticmethod
    def error(msg: str):
        print(f"❌ [ERROR] {msg}")

# --- NETWORK LAYER ---
class APIClient:
    """Handles HTTP requests with robust error handling and retry logic."""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})

    def fetch(self, url: str, params: Optional[Dict] = None) -> Optional[Dict]:
        """Executes a GET request with automatic retries."""
        for attempt in range(1, CONFIG["MAX_RETRIES"] + 1):
            try:
                response = self.session.get(url, params=params, timeout=CONFIG["TIMEOUT"])
                
                # Check for 404 specifically (common for missing streams)
                if response.status_code == 404:
                    return None
                
                response.raise_for_status()
                return response.json()

            except requests.exceptions.RequestException as e:
                if attempt == CONFIG["MAX_RETRIES"]:
                    Logger.error(f"Request failed after {attempt} attempts: {url}")
                    return None
                time.sleep(CONFIG["RETRY_DELAY"])
            except json.JSONDecodeError:
                Logger.error(f"Invalid JSON response from: {url}")
                return None
        return None

# --- SERVICE LAYER ---
class MediaService:
    """Orchestrates metadata fetching from TMDB and Stream fetching from Stremio."""

    def __init__(self):
        self.client = APIClient()

    def search_tmdb(self, query: str) -> List[Dict[str, Any]]:
        """Searches TMDB for movies and TV shows."""
        url = "https://api.themoviedb.org/3/search/multi"
        params = {
            "api_key": CONFIG["TMDB_API_KEY"],
            "query": query,
            "include_adult": "false"
        }
        data = self.client.fetch(url, params)
        if not data: return []

        results = []
        for item in data.get("results", []):
            if item.get("media_type") not in ["movie", "tv"]:
                continue
            
            # Normalize title and date
            title = item.get("title") or item.get("name")
            date = item.get("release_date") or item.get("first_air_date") or "N/A"
            
            results.append({
                "id": item["id"],
                "type": item["media_type"],
                "title": title,
                "year": date[:4],
                "overview": item.get("overview", "")
            })
        return results

    def get_tv_details(self, tmdb_id: int) -> Dict:
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}"
        params = {"api_key": CONFIG["TMDB_API_KEY"]}
        return self.client.fetch(url, params) or {}

    def get_season_episodes(self, tmdb_id: int, season_number: int) -> List[Dict]:
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}/season/{season_number}"
        params = {"api_key": CONFIG["TMDB_API_KEY"]}
        data = self.client.fetch(url, params)
        return data.get("episodes", []) if data else []

    def get_stream_url(self, tmdb_id: int, season: Optional[int] = None, episode: Optional[int] = None) -> List[Dict]:
        """Constructs the backend ID and fetches available streams."""
        if season is not None:
            # TV Show ID Format: {TMDB}-{DB_INDEX}:{SEASON}:{EPISODE}
            stream_id = f"{tmdb_id}-{CONFIG['DB_INDEX']}:{season}:{episode}"
            endpoint = "series"
        else:
            # Movie ID Format: {TMDB}-{DB_INDEX}
            stream_id = f"{tmdb_id}-{CONFIG['DB_INDEX']}"
            endpoint = "movie"

        url = f"{CONFIG['STREMIO_BASE_URL']}/stremio/stream/{endpoint}/{stream_id}.json"
        
        # Suppress errors for missing streams (common scenario)
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                return data.get("streams", [])
        except:
            pass
        return []

# --- APPLICATION LOGIC ---
class M3UGenerator:
    """Manages playlist construction and file output."""

    def __init__(self):
        self.service = MediaService()
        self.playlists = {
            "1080p": ["#EXTM3U"],
            "720p":  ["#EXTM3U"],
            "480p":  ["#EXTM3U"]
        }
        self.stats = {"found": 0, "processed": 0}

    def add_entry(self, title: str, streams: List[Dict], thumb: str):
        """Filters streams by quality and adds them to the respective playlist."""
        added_qualities = set()
        
        for stream in streams:
            # Normalize stream metadata for regex matching
            raw_meta = (stream.get("name", "") + " " + stream.get("title", "")).lower()
            url = stream.get("url")
            
            if not url: continue

            # Quality Matching Logic
            entry = f'#EXTINF:-1 tvg-logo="{thumb}",{title}\n{url}'
            
            if "1080" in raw_meta and "1080p" not in added_qualities:
                self.playlists["1080p"].append(entry)
                added_qualities.add("1080p")
            elif "720" in raw_meta and "720p" not in added_qualities:
                self.playlists["720p"].append(entry)
                added_qualities.add("720p")
            elif "480" in raw_meta and "480p" not in added_qualities:
                self.playlists["480p"].append(entry)
                added_qualities.add("480p")
        
        if added_qualities:
            self.stats["found"] += 1
            Logger.success(f"Streams found for: {title} | Q: {list(added_qualities)}")

    def process_selection(self, media: Dict):
        Logger.info(f"Starting Extraction: {media['title']} ({media['year']})")
        print("-" * 60)

        if media["type"] == "movie":
            streams = self.service.get_stream_url(media["id"])
            if streams:
                self.add_entry(media["title"], streams, "")
            else:
                Logger.warning("No streams found in backend.")

        elif media["type"] == "tv":
            details = self.service.get_tv_details(media["id"])
            total_seasons = details.get("number_of_seasons", 0)

            for s in range(1, total_seasons + 1):
                Logger.info(f"Scanning Season {s}...")
                episodes = self.service.get_season_episodes(media["id"], s)
                
                season_has_content = False
                for ep in episodes:
                    s_num, e_num = ep["season_number"], ep["episode_number"]
                    ep_title = f"{media['title']} S{s_num:02d}E{e_num:02d} - {ep['name']}"
                    
                    # Construct high-res thumbnail URL
                    thumb = f"https://image.tmdb.org/t/p/w500{ep['still_path']}" if ep.get("still_path") else ""
                    
                    streams = self.service.get_stream_url(media["id"], s_num, e_num)
                    if streams:
                        self.add_entry(ep_title, streams, thumb)
                        season_has_content = True
                    
                    # Rate limiting protection
                    time.sleep(0.05)

                if not season_has_content:
                    Logger.warning(f"Season {s}: No content found.")

    def save_playlists(self, base_filename: str):
        """Saves generated playlists to disk."""
        safe_name = re.sub(r'[\\/*?:"<>|]', "", base_filename).replace(" ", "_")
        files_saved = False

        print("\n" + "-" * 60)
        for quality, content in self.playlists.items():
            if len(content) > 1: # Only save if we have more than just the header
                filename = f"{safe_name}_{quality}.m3u"
                try:
                    with open(filename, "w", encoding="utf-8") as f:
                        f.write("\n".join(content))
                    Logger.success(f"Generated Playlist: {filename}")
                    files_saved = True
                except IOError as e:
                    Logger.error(f"Failed to write file {filename}: {e}")

        if not files_saved:
            Logger.error("No valid streams were found. No files generated.")

def main():
    try:
        # Interactive Search Phase
        generator = M3UGenerator()
        print("\n🔎 SEARCH DATABASE")
        query = input("👉 Enter Movie/Series Name: ").strip()
        
        if not query:
            Logger.error("Search query cannot be empty.")
            return

        results = generator.service.search_tmdb(query)
        if not results:
            Logger.error("No results found on TMDB.")
            return

        print(f"\n📺 Search Results:")
        for idx, item in enumerate(results):
            print(f"   {idx + 1}. {item['title']} ({item['year']}) [{item['type'].upper()}]")

        # Selection Phase
        try:
            choice = int(input("\n🔢 Select Number: ")) - 1
            if choice < 0 or choice >= len(results):
                raise ValueError
        except ValueError:
            Logger.error("Invalid selection.")
            return

        # Processing Phase
        selected = results[choice]
        generator.process_selection(selected)
        generator.save_playlists(selected['title'])

    except KeyboardInterrupt:
        print("\n\n🛑 Operation cancelled by user.")
        sys.exit(0)
    except Exception as e:
        Logger.error(f"An unexpected error occurred: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# 3. Execute the Python Logic
# We run python3 specifically to ensure environment compatibility
python3 m3u_core.py
