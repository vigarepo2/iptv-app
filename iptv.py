from flask import Flask, request, render_template_string, send_file, redirect, url_for
import requests
import os
from datetime import datetime

app = Flask(__name__)

# Directory to store downloaded playlists
DOWNLOAD_DIR = "downloads"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

def fetch_m3u_playlist(url):
    """Fetch an M3U playlist from the given URL."""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.text
    except requests.RequestException as e:
        return f"Error fetching playlist: {e}"

def save_playlist(playlist_content, filename):
    """Save the playlist content to a file."""
    filepath = os.path.join(DOWNLOAD_DIR, filename)
    with open(filepath, "w", encoding="utf-8") as file:
        file.write(playlist_content)
    return filepath

# HTML template embedded in the Python script
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV Playlist Downloader</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f4f4f9;
            color: #333;
        }
        .container {
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
            background: #fff;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        h1 {
            text-align: center;
            color: #4CAF50;
        }
        form {
            display: flex;
            flex-direction: column;
        }
        input[type="text"] {
            padding: 10px;
            margin-bottom: 10px;
            border: 1px solid #ccc;
            border-radius: 4px;
        }
        button {
            padding: 10px;
            background-color: #4CAF50;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }
        button:hover {
            background-color: #45a049;
        }
        .error {
            color: red;
            text-align: center;
        }
        .success {
            color: green;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>IPTV Playlist Downloader</h1>
        {% if error %}
            <p class="error">{{ error }}</p>
        {% endif %}
        {% if success %}
            <p class="success">{{ success }}</p>
        {% endif %}
        <form method="POST">
            <input type="text" name="playlist_url" placeholder="Enter M3U Playlist URL" required>
            <button type="submit">Download Playlist</button>
        </form>
    </div>
</body>
</html>
"""

@app.route("/", methods=["GET", "POST"])
def index():
    """Render the main page and handle form submissions."""
    error = None
    success = None
    if request.method == "POST":
        playlist_url = request.form.get("playlist_url")
        if not playlist_url:
            error = "Please provide a valid URL."
        else:
            # Fetch the playlist
            playlist_content = fetch_m3u_playlist(playlist_url)
            if playlist_content.startswith("Error"):
                error = playlist_content
            else:
                # Generate a unique filename
                timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
                filename = f"playlist_{timestamp}.txt"
                
                # Save the playlist
                save_playlist(playlist_content, filename)
                
                # Set success message
                success = f"Playlist downloaded successfully! <a href='/download/{filename}'>Click here to download</a>."
    
    return render_template_string(HTML_TEMPLATE, error=error, success=success)

@app.route("/download/<filename>")
def download(filename):
    """Serve the downloaded playlist file."""
    filepath = os.path.join(DOWNLOAD_DIR, filename)
    if os.path.exists(filepath):
        return send_file(filepath, as_attachment=True)
    return "File not found.", 404

if __name__ == "__main__":
    app.run(debug=True)
