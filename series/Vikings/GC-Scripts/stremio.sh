#!/bin/bash

# ==============================================================================
# Script Name: stremio.sh
# Description: Professional M3U Generator with Bulletproof Image Handling
# Author:      VigaRepo (Fixed Logic)
# ==============================================================================

# 1. Setup
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║           🚀 Initializing Stremio M3U Generator (Fixed)            ║"
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
from typing import List, Dict, Optional

# --- CONFIGURATION ---
CONFIG = {
    "STREMIO_BASE_URL": "https://stremio--stremio--m72vl4mnxzkd.code.run",
    "TMDB_API_KEY": "f320fa5c189058be63b5420c044f64e1",
    "DB_INDEX": "1",
    "TIMEOUT": 15,
    "RETRIES": 3,
    "PLACEHOLDER_IMG": "https://placehold.co/600x400/000000/FFFFFF/png?text=No+Image"
}

class Logger:
    @staticmethod
    def log(msg, icon="ℹ️"):
        print(f"{icon} {msg}")

class APIClient:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})

    def get(self, url: str, params: Optional[Dict] = None) -> Optional[Dict]:
        for attempt in range(CONFIG["RETRIES"]):
            try:
                response = self.session.get(url, params=params, timeout=CONFIG["TIMEOUT"])
                if response.status_code == 404: return None
                response.raise_for_status()
                return response.json()
            except Exception:
                time.sleep(1)
        return None

class MediaService:
    def __init__(self):
        self.client = APIClient()

    def get_best_image(self, media_type: str, media_id: int, fallback_backdrop: str, fallback_poster: str) -> str:
        """
        Priority:
        1. English Logo (Transparent)
        2. Any Logo
        3. Landscape Backdrop
        4. Poster
        5. Placeholder
        """
        url = f"https://api.themoviedb.org/3/{media_type}/{media_id}/images"
        params = {"api_key": CONFIG["TMDB_API_KEY"], "include_image_language": "en,null"}
        
        data = self.client.get(url, params)
        
        # 1. Try English/Null Logos
        if data and "logos" in data and len(data["logos"]) > 0:
            best = sorted(data["logos"], key=lambda x: x.get("vote_average", 0), reverse=True)[0]
            return f"https://image.tmdb.org/t/p/original{best['file_path']}"

        # 2. Try Fetching ANY Logo (Relaxed Filter)
        params["include_image_language"] = None
        data = self.client.get(url, params)
        if data and "logos" in data and len(data["logos"]) > 0:
            best = sorted(data["logos"], key=lambda x: x.get("vote_average", 0), reverse=True)[0]
            return f"https://image.tmdb.org/t/p/original{best['file_path']}"

        # 3. Fallback to Backdrop
        if fallback_backdrop:
            return f"https://image.tmdb.org/t/p/original{fallback_backdrop}"
            
        # 4. Fallback to Poster
        if fallback_poster:
            return f"https://image.tmdb.org/t/p/original{fallback_poster}"

        # 5. Give up
        return CONFIG["PLACEHOLDER_IMG"]

    def search_tmdb(self, query: str) -> List[Dict]:
        url = "https://api.themoviedb.org/3/search/multi"
        params = {
            "api_key": CONFIG["TMDB_API_KEY"],
            "query": query,
            "include_adult": "false",
            "language": "en-US"
        }
        data = self.client.get(url, params)
        if not data: return []

        results = []
        for item in data.get("results", []):
            if item.get("media_type") not in ["movie", "tv"]: continue
            
            # Safe Metadata Extraction
            results.append({
                "id": item.get("id"),
                "type": item.get("media_type"),
                "title": item.get("title") or item.get("name") or "Unknown",
                "year": (item.get("release_date") or item.get("first_air_date") or "N/A")[:4],
                "backdrop_path": item.get("backdrop_path"),
                "poster_path": item.get("poster_path")
            })
        return results

    def get_tv_data(self, tmdb_id: int) -> Dict:
        return self.client.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}", {"api_key": CONFIG["TMDB_API_KEY"]}) or {}

    def get_episodes(self, tmdb_id: int, season: int) -> List[Dict]:
        data = self.client.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}/season/{season}", {"api_key": CONFIG["TMDB_API_KEY"]})
        return data.get("episodes", []) if data else []

    def get_streams(self, tmdb_id: int, season=None, episode=None) -> List[Dict]:
        endpoint = "series" if season is not None else "movie"
        sid = f"{tmdb_id}-{CONFIG['DB_INDEX']}"
        if season is not None: sid += f":{season}:{episode}"

        url = f"{CONFIG['STREMIO_BASE_URL']}/stremio/stream/{endpoint}/{sid}.json"
        data = self.client.get(url)
        return data.get("streams", []) if data else []

class PlaylistGenerator:
    def __init__(self):
        self.service = MediaService()
        self.playlists = {"1080p": ["#EXTM3U"], "720p": ["#EXTM3U"], "480p": ["#EXTM3U"]}
        self.count = 0

    def add_track(self, title: str, streams: List[Dict], logo_url: str):
        added = set()
        for s in streams:
            name_meta = (s.get("name", "") + " " + s.get("title", "")).lower()
            url = s.get("url")
            if not url: continue

            # Clean Title
            clean_title = title.replace(",", " -").strip()
            entry = f'#EXTINF:-1 group-title="Stremio" tvg-logo="{logo_url}",{clean_title}\n{url}'

            if "1080" in name_meta and "1080p" not in added:
                self.playlists["1080p"].append(entry)
                added.add("1080p")
            elif "720" in name_meta and "720p" not in added:
                self.playlists["720p"].append(entry)
                added.add("720p")
            elif "480" in name_meta and "480p" not in added:
                self.playlists["480p"].append(entry)
                added.add("480p")
        
        if added:
            self.count += 1
            Logger.log(f"Added: {title} | Quality: {list(added)}", "✅")

    def run(self):
        print("\n🔎 TMDB Search")
        query = input("👉 Enter Name: ").strip()
        if not query: return

        results = self.service.search_tmdb(query)
        if not results:
            Logger.log("No results found.", "❌")
            return

        print(f"\n📺 Found {len(results)} results:")
        for idx, item in enumerate(results):
            print(f"   {idx + 1}. {item['title']} ({item['year']}) [{item['type'].upper()}]")

        try:
            choice = int(input("\n🔢 Select Number: ")) - 1
            if choice < 0 or choice >= len(results): raise ValueError
        except:
            Logger.log("Invalid selection.", "❌")
            return

        media = results[choice]
        print(f"\n🚀 Processing: {media['title']}")
        print("-" * 60)

        # --- MOVIE LOGIC ---
        if media["type"] == "movie":
            # Smart Image Fetcher
            image = self.service.get_best_image(
                "movie", 
                media["id"], 
                media.get("backdrop_path"), 
                media.get("poster_path")
            )
            streams = self.service.get_streams(media["id"])
            if streams:
                self.add_track(media["title"], streams, image)
            else:
                Logger.log("No streams found in backend.", "⚠️")

        # --- TV SHOW LOGIC ---
        elif media["type"] == "tv":
            details = self.service.get_tv_data(media["id"])
            seasons = details.get("number_of_seasons", 0)

            for s in range(1, seasons + 1):
                Logger.log(f"Scanning Season {s}...", "📂")
                episodes = self.service.get_episodes(media["id"], s)
                
                for ep in episodes:
                    s_num, e_num = ep["season_number"], ep["episode_number"]
                    ep_name = ep.get("name", f"Episode {e_num}")
                    ep_title = f"{media['title']} S{s_num:02d}E{e_num:02d} - {ep_name}"
                    
                    # Episode Still
                    thumb_path = ep.get("still_path")
                    thumb = f"https://image.tmdb.org/t/p/original{thumb_path}" if thumb_path else CONFIG["PLACEHOLDER_IMG"]
                    
                    streams = self.service.get_streams(media["id"], s_num, e_num)
                    if streams:
                        self.add_track(ep_title, streams, thumb)
                    time.sleep(0.05)

        # --- SAVE ---
        print("-" * 60)
        safe_name = re.sub(r'[\\/*?:"<>|]', "", media['title']).replace(" ", "_")
        saved = False

        for q, content in self.playlists.items():
            if len(content) > 1:
                fname = f"{safe_name}_{q}.m3u"
                with open(fname, "w", encoding="utf-8") as f:
                    f.write("\n".join(content))
                Logger.log(f"Generated: {fname}", "💾")
                saved = True
        
        if not saved:
            Logger.log("No valid playlists generated.", "⚠️")

if __name__ == "__main__":
    try:
        PlaylistGenerator().run()
    except KeyboardInterrupt:
        print("\nCancelled.")
EOF

# 3. Execute
python3 m3u_core.py
