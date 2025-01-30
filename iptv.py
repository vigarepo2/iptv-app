from flask import Flask, request, jsonify, render_template_string
import os

app = Flask(__name__)

HTML_CONTENT = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV Player</title>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <script src="https://cdn.jsdelivr.net/npm/video.js@7.20.3/dist/video.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/videojs-hls-quality-selector@1.1.3/dist/videojs-hls-quality-selector.min.js"></script>
    <link href="https://cdn.jsdelivr.net/npm/video.js@7.20.3/dist/video-js.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
    <style>
        body { background-color: #121212; color: white; font-family: Arial, sans-serif; }
        .container { max-width: 1200px; margin: 20px auto; }
        #video-container { margin-top: 20px; }
        .channel-list { max-height: 400px; overflow-y: auto; }
        .video-js { width: 100%; height: 500px; background: #000; }
        .btn-custom { margin-top: 10px; }
        .controls { margin-top: 10px; display: flex; gap: 10px; }
        .folder { cursor: pointer; color: #0d6efd; }
        .video-js .vjs-control-bar { background: rgba(0, 0, 0, 0.7); }
    </style>
    <script>
        let player;

        function fetchChannels(type, data) {
            fetch('/fetch_channels', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: type, ...data })
            })
            .then(response => response.json())
            .then(data => {
                let channelList = document.getElementById("channel-list");
                channelList.innerHTML = "";
                if (data.channels && data.channels.length > 0) {
                    data.channels.forEach(channel => {
                        let btn = document.createElement("button");
                        btn.className = "list-group-item list-group-item-action";
                        btn.textContent = channel.name;
                        btn.onclick = function() { playChannel(channel.url); };
                        channelList.appendChild(btn);
                    });
                } else if (data.folders && data.folders.length > 0) {
                    data.folders.forEach(folder => {
                        let div = document.createElement("div");
                        div.className = "folder";
                        div.textContent = folder.name;
                        div.onclick = function() { fetchChannels('folder', { path: folder.path }); };
                        channelList.appendChild(div);
                    });
                } else {
                    channelList.innerHTML = "<p class='text-danger'>No channels or folders found!</p>";
                }
            });
        }

        function uploadM3U() {
            let fileInput = document.getElementById("m3u-file");
            let file = fileInput.files[0];

            let reader = new FileReader();
            reader.onload = function(event) {
                localStorage.setItem('m3uFile', event.target.result);
                fetchChannels("m3u", { filename: file.name, content: event.target.result });
            };
            reader.readAsText(file);
        }

        function fetchFromURL() {
            let url = document.getElementById("m3u-url").value;
            fetchChannels("url", { url: url });
        }

        function playChannel(url) {
            let videoContainer = document.getElementById('video-container');
            videoContainer.style.display = 'block';

            if (player) {
                player.dispose();
            }

            player = videojs('video-player', {
                controls: true,
                autoplay: true,
                fluid: true,
                html5: {
                    hls: {
                        enableLowInitialPlaylist: true,
                        smoothQualityChange: true,
                        overrideNative: true
                    }
                }
            });

            player.hlsQualitySelector({
                displayCurrentQuality: true,
            });

            player.src({ src: url, type: 'application/x-mpegURL' });
            player.play();
        }

        function loadLocalStorage() {
            let m3uContent = localStorage.getItem('m3uFile');
            if (m3uContent) {
                fetchChannels("m3u", { content: m3uContent });
            }
        }

        window.onload = loadLocalStorage;
    </script>
</head>
<body>
    <div class="container">
        <h1 class="text-center">IPTV Player</h1>

        <div class="mb-3">
            <label class="form-label">Upload M3U File:</label>
            <input type="file" id="m3u-file" class="form-control">
            <button class="btn btn-primary btn-custom" onclick="uploadM3U()">Upload & Load</button>
        </div>

        <div class="mb-3">
            <label class="form-label">Fetch from M3U URL:</label>
            <input type="text" id="m3u-url" class="form-control" placeholder="Enter M3U URL">
            <button class="btn btn-success btn-custom" onclick="fetchFromURL()">Fetch & Load</button>
        </div>

        <h3>Channels</h3>
        <div id="channel-list" class="list-group channel-list"></div>

        <div id="video-container">
            <h3>Now Playing</h3>
            <video id="video-player" class="video-js vjs-default-skin" controls>
                <track kind="captions" src="" label="Subtitles" default>
            </video>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def index():
    return HTML_CONTENT

@app.route('/fetch_channels', methods=['POST'])
def fetch_channels():
    data = request.json
    source_type = data.get('type')
    channels = []
    folders = []

    if source_type == "m3u":
        content = data.get('content')
        if content:
            channels = parse_m3u(content)
    
    elif source_type == "url":
        url = data.get('url')
        if url:
            try:
                response = requests.get(url)
                if response.status_code == 200:
                    channels = parse_m3u(response.text)
            except:
                return jsonify({'error': 'Failed to fetch M3U URL'}), 400

    elif source_type == "folder":
        path = data.get('path')
        if path:
            channels, folders = fetch_folder_content(path)

    return jsonify({'channels': channels, 'folders': folders})

def parse_m3u(content):
    lines = content.splitlines()
    channels = []
    current_name = None

    for line in lines:
        line = line.strip()
        if line.startswith("#EXTINF:"):
            current_name = line.split(",")[-1]
        elif line and not line.startswith("#"):
            if current_name:
                channels.append({"name": current_name, "url": line})
                current_name = None

    return channels

def fetch_folder_content(path):
    channels = []
    folders = []
    for root, dirs, files in os.walk(path):
        for dir in dirs:
            folders.append({"name": dir, "path": os.path.join(root, dir)})
        for file in files:
            if file.endswith('.m3u'):
                with open(os.path.join(root, file), 'r') as f:
                    channels.extend(parse_m3u(f.read()))
    return channels, folders

if __name__ == '__main__':
    app.run(debug=True)
