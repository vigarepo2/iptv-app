from flask import Flask, request, render_template_string, send_file, redirect, url_for
import requests
import os
from datetime import datetime

app = Flask(__name__)

# Use the temporary directory for saving files
DOWNLOAD_DIR = "/tmp/downloads"
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
            font-family: 'Arial', sans-serif;
            margin: 0;
            padding: 0;
            background: linear-gradient(to bottom, #4CAF50, #81C784);
            color: #fff;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            max-width: 600px;
            padding: 40px;
            background: rgba(0, 0, 0, 0.6);
            border-radius: 10px;
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.3);
            text-align: center;
        }
        h1 {
            font-size: 2rem;
            margin-bottom: 20px;
        }
        form {
            display: flex;
            flex-direction: column;
        }
        input[type="text"] {
            padding: 15px;
            margin-bottom: 15px;
            border: none;
            border-radius: 5px;
            font-size: 1rem;
        }
        button {
            padding: 15px;
            background-color: #FFC107;
            color: #000;
            border: none;
            border-radius: 5px;
            font-size: 1rem;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }
        button:hover {
            background-color: #FFA000;
        }
        .error {
            color: red;
            margin-top: 10px;
        }
        .success {
            color: #4CAF50;
            margin-top: 10px;
        }
        .download-link {
            color: #FFC107;
            text-decoration: none;
            font-weight: bold;
        }
        .download-link:hover {
            text-decoration: underline;
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
            <input type="text" name="playlist_url" placeholder="Enter M3U Playlist URL (Xtream, Stalker, MAC)" required>
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
                
                # Set success message with a working download link
                download_link = url_for("download", filename=filename, _external=True)
                success = f"Playlist downloaded successfully! <a href='{download_link}' class='download-link'>Click here to download</a>."
    
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
