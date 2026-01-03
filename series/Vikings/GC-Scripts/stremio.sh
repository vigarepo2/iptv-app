#!/bin/bash

# 1. Install Dependencies quietly
echo "🚀 Initializing Stremio-to-M3U Environment..."
pip install -q requests

# 2. Create the Python Logic File
# We use 'EOF' to prevent variable expansion issues in bash
cat << 'EOF' > m3u_generator.py
import requests
import time
import re
import sys

# Try to import google.colab to handle downloads
try:
    from google.colab import files
    IN_COLAB = True
except ImportError:
    IN_COLAB = False

# --- CONFIGURATION ---
STREMIO_BASE_URL = "https://stremio--stremio--m72vl4mnxzkd.code.run"
TMDB_API_KEY = "f320fa5c189058be63b5420c044f64e1"
DB_INDEX = "1"  
# ---------------------

class MediaFetcher:
    def __init__(self):
        self.headers = {"accept": "application/json"}

    def search_tmdb(self, query):
        url = f"https://api.themoviedb.org/3/search/multi?api_key={TMDB_API_KEY}&query={query}&include_adult=false"
        try:
            resp = requests.get(url, headers=self.headers).json()
            return [
                {
                    "id": x["id"],
                    "type": x["media_type"],
                    "title": x.get("title") or x.get("name"),
                    "year": (x.get("release_date") or x.get("first_air_date") or "N/A")[:4],
                    "overview": x.get("overview", "")
                }
                for x in resp.get("results", [])
                if x["media_type"] in ["movie", "tv"]
            ]
        except Exception as e:
            print(f"❌ TMDB Search Error: {e}")
            return []

    def get_tv_details(self, tmdb_id):
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}?api_key={TMDB_API_KEY}"
        return requests.get(url).json()

    def get_season_episodes(self, tmdb_id, season_num):
        url = f"https://api.themoviedb.org/3/tv/{tmdb_id}/season/{season_num}?api_key={TMDB_API_KEY}"
        resp = requests.get(url)
        return resp.json().get("episodes", []) if resp.status_code == 200 else []

    def get_stremio_stream(self, tmdb_id, season=None, episode=None):
        if season is not None:
            sid = f"{tmdb_id}-{DB_INDEX}:{season}:{episode}"
            endpoint = "series"
        else:
            sid = f"{tmdb_id}-{DB_INDEX}"
            endpoint = "movie"

        url = f"{STREMIO_BASE_URL}/stremio/stream/{endpoint}/{sid}.json"
        try:
            resp = requests.get(url, timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                return data.get("streams", [])
        except:
            pass
        return []

    def generate_playlist(self, media_info):
        print(f"\n🚀 Processing: {media_info['title']} ({media_info['year']})")
        print("-" * 50)

        playlists = {"1080p": ["#EXTM3U"], "720p": ["#EXTM3U"], "480p": ["#EXTM3U"]}
        total_found = 0

        if media_info['type'] == 'movie':
            streams = self.get_stremio_stream(media_info['id'])
            if streams:
                self._add_to_playlist(playlists, media_info['title'], streams, "")
                total_found += 1
                print(f"   ✅ Movie Found: {media_info['title']}")
            else:
                print("   ❌ Movie not found in Stremio backend.")

        elif media_info['type'] == 'tv':
            details = self.get_tv_details(media_info['id'])
            seasons = details.get('number_of_seasons', 0)
            
            for s in range(1, seasons + 1):
                print(f"   📂 Scanning Season {s}...")
                episodes = self.get_season_episodes(media_info['id'], s)
                season_has_content = False

                for ep in episodes:
                    s_num, e_num = ep['season_number'], ep['episode_number']
                    ep_title = f"{media_info['title']} S{s_num:02d}E{e_num:02d} - {ep['name']}"
                    thumb = f"https://image.tmdb.org/t/p/w500{ep['still_path']}" if ep.get('still_path') else ""
                    
                    streams = self.get_stremio_stream(media_info['id'], s_num, e_num)
                    if streams:
                        self._add_to_playlist(playlists, ep_title, streams, thumb)
                        total_found += 1
                        season_has_content = True
                        print(f"      ✅ Found: {ep_title}")
                    
                    time.sleep(0.05) 

                if not season_has_content:
                    print(f"      ⚠️ No links for Season {s}")

        return playlists, total_found

    def _add_to_playlist(self, playlists, title, streams, thumb):
        added_qualities = []
        for s in streams:
            name = (s.get("name") + s.get("title")).lower()
            url = s.get("url")
            
            if "1080" in name and "1080p" not in added_qualities:
                playlists["1080p"].append(f'#EXTINF:-1 tvg-logo="{thumb}",{title}\n{url}')
                added_qualities.append("1080p")
            elif "720" in name and "720p" not in added_qualities:
                playlists["720p"].append(f'#EXTINF:-1 tvg-logo="{thumb}",{title}\n{url}')
                added_qualities.append("720p")
            elif "480" in name and "480p" not in added_qualities:
                playlists["480p"].append(f'#EXTINF:-1 tvg-logo="{thumb}",{title}\n{url}')
                added_qualities.append("480p")

def main():
    fetcher = MediaFetcher()
    print("\n🔎 SEARCH DATABASE")
    query = input("👉 Enter Name: ").strip()
    if not query: return

    results = fetcher.search_tmdb(query)
    
    if not results:
        print("❌ No results found on TMDB.")
        return

    print(f"\n📺 Found {len(results)} results:")
    for i, item in enumerate(results):
        print(f"   {i+1}. {item['title']} ({item['year']}) [{item['type'].upper()}]")

    try:
        selection = int(input("\n🔢 Select Number: ")) - 1
        if selection < 0 or selection >= len(results): raise ValueError
    except:
        print("❌ Invalid selection.")
        return

    selected_media = results[selection]
    playlists, count = fetcher.generate_playlist(selected_media)

    if count == 0:
        print("\n❌ No stream links found in your Stremio backend for this selection.")
        return

    print(f"\n✨ Generation Complete! Found {count} playable items.")
    safe_title = re.sub(r'[\\/*?:"<>|]', "", selected_media['title']).replace(" ", "_")

    files_generated = False
    for quality, content in playlists.items():
        if len(content) > 1:
            fname = f"{safe_title}_{quality}.m3u"
            with open(fname, "w", encoding="utf-8") as f:
                f.write("\n".join(content))
            print(f"💾 Saving {fname}...")
            
            if IN_COLAB:
                files.download(fname)
            else:
                print(f"   --> File saved locally: {fname}")
            files_generated = True
            
    if not files_generated:
        print("⚠️ No valid streams extracted for 1080p, 720p, or 480p.")

if __name__ == "__main__":
    main()
EOF

# 3. Run the Python Script
echo "▶️ Starting Interactive Tool..."
python m3u_generator.py
