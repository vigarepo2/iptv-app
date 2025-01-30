from flask import Flask, request, jsonify, render_template_string
import os
import requests

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
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #1e1e2f;
            color: #ffffff;
            font-family: 'Roboto', sans-serif;
            margin: 0;
            padding: 0;
            overflow-x: hidden;
        }
        .sidebar {
            height: 100vh;
            width: 250px;
            background-color: #2a2b3d;
            position: fixed;
            top: 0;
            left: 0;
            overflow-y: auto;
            transition: width 0.3s;
        }
        .sidebar.collapsed {
            width: 60px;
        }
        .sidebar h3 {
            text-align: center;
            margin: 20px 0;
            font-size: 1.2rem;
        }
        .sidebar button {
            background: none;
            border: none;
            color: #ffffff;
            padding: 10px 15px;
            cursor: pointer;
            width: 100%;
            text-align: left;
            transition: background-color 0.3s;
        }
        .sidebar button:hover {
            background-color: #3c3d53;
        }
        .main-content {
            margin-left: 250px;
            transition: margin-left 0.3s;
        }
        .main-content.collapsed {
            margin-left: 60px;
        }
        .video-container {
            display: flex;
            justify-content: center;
            align-items: center;
            height: calc(100vh - 100px);
        }
        .video-js {
            width: 90%;
            height: 80%;
            background-color: #000000;
        }
        .controls {
            padding: 20px;
        }
        .controls input, .controls button {
            margin: 5px;
            padding: 10px;
            border-radius: 5px;
            border: none;
            cursor: pointer;
        }
        .controls input {
            background-color: #ffffff;
            color: #000000;
        }
        .controls button {
            background-color: #4caf50;
            color: #ffffff;
        }
        .controls button:hover {
            background-color: #45a049;
        }
        .toggle-sidebar {
            position: absolute;
            top: 10px;
            left: 260px;
            cursor: pointer;
            z-index: 1000;
        }
        .toggle-sidebar.collapsed {
            left: 70px;
        }
    </style>
</head>
<body>
    <div class="sidebar" id="sidebar">
        <h3>Channels</h3>
        <div id="channel-list" class="list-group"></div>
    </div>
    <div class="main-content" id="main-content">
        <div class="controls p-3">
            <button onclick="toggleSidebar()" class="btn btn-secondary toggle-sidebar" id="toggle-sidebar">☰</button>
            <input type="file" id="m3u-file" class="form-control" placeholder="Upload M3U File">
            <button class="btn btn-primary" onclick="uploadM3U()">Upload & Load</button>
            <input type="text" id="m3u-url" class="form-control" placeholder="Enter M3U URL">
            <button class="btn btn-success" onclick="fetchFromURL()">Fetch & Load</button>
            <h4>Xtream Codes Login</h4>
            <input type="text" id="xtream-username" class="form-control" placeholder="Username">
            <input type="password" id="xtream-password" class="form-control" placeholder="Password">
            <input type="text" id="xtream-server" class="form-control" placeholder="Server URL">
            <button class="btn btn-warning" onclick="loginXtream()">Login</button>
            <h4>Stalker Portal Login</h4>
            <input type="text" id="stalker-mac" class="form-control" placeholder="MAC Address">
            <input type="text" id="stalker-server" class="form-control" placeholder="Server URL">
            <button class="btn btn-info" onclick="loginStalker()">Login</button>
        </div>
        <div class="video-container">
            <video id="video-player" class="video-js vjs-default-skin" controls preload="auto" data-setup='{}'></video>
        </div>
    </div>
    <script>
        let player;
        let isSidebarCollapsed = false;

        function toggleSidebar() {
            const sidebar = document.getElementById('sidebar');
            const mainContent = document.getElementById('main-content');
            const toggleButton = document.getElementById('toggle-sidebar');
            if (isSidebarCollapsed) {
                sidebar.classList.remove('collapsed');
                mainContent.classList.remove('collapsed');
                toggleButton.classList.remove('collapsed');
                isSidebarCollapsed = false;
            } else {
                sidebar.classList.add('collapsed');
                mainContent.classList.add('collapsed');
                toggleButton.classList.add('collapsed');
                isSidebarCollapsed = true;
            }
        }

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
                        btn.textContent = channel.name;
                        btn.onclick = function() { playChannel(channel.url); };
                        channelList.appendChild(btn);
                    });
                } else {
                    channelList.innerHTML = "<p class='text-danger'>No channels found!</p>";
                }
            });
        }

        function uploadM3U() {
            let fileInput = document.getElementById("m3u-file");
            let file = fileInput.files[0];
            let reader = new FileReader();
            reader.onload = function(event) {
                localStorage.setItem(file.name, event.target.result);
                fetchChannels("m3u", { filename: file.name, content: event.target.result });
            };
            reader.readAsText(file);
        }

        function fetchFromURL() {
            let url = document.getElementById("m3u-url").value;
            fetchChannels("url", { url: url });
        }

        function playChannel(url) {
            if (player) {
                player.dispose();
            }

            const videoElement = document.getElementById('video-player');
            player = videojs(videoElement, {
                controls: true,
                autoplay: true,
                fluid: true,
                html5: {
                    hls: {
                        overrideNative: !videojs.browser.IS_SAFARI
                    }
                }
            });

            player.hlsQualitySelector();

            if (videojs.Hls.isSupported()) {
                const hls = new Hls();
                hls.loadSource(url);
                hls.attachMedia(videoElement);
                hls.on(Hls.Events.ERROR, function(event, data) {
                    console.error("HLS Error:", data);
                    alert("Error loading stream. Please check the URL.");
                });
            } else if (videoElement.canPlayType('application/vnd.apple.mpegurl')) {
                videoElement.src = url;
                videoElement.addEventListener('error', function() {
                    console.error("Native HLS Error:", videoElement.error);
                    alert("Error loading stream. Please check the URL.");
                });
            } else {
                alert("Your browser does not support HLS streaming.");
            }

            player.play();
        }

        function loginXtream() {
            let username = document.getElementById("xtream-username").value;
            let password = document.getElementById("xtream-password").value;
            let server = document.getElementById("xtream-server").value;
            fetchChannels("xtream", { username: username, password: password, server: server });
        }

        function loginStalker() {
            let mac = document.getElementById("stalker-mac").value;
            let server = document.getElementById("stalker-server").value;
            fetchChannels("stalker", { mac: mac, server: server });
        }
    </script>
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
            except Exception as e:
                return jsonify({'error': f'Failed to fetch M3U URL: {str(e)}'}), 400

    elif source_type == "xtream":
        username = data.get('username')
        password = data.get('password')
        server = data.get('server')
        if username and password and server:
            channels = fetch_xtream_channels(username, password, server)

    elif source_type == "stalker":
        mac = data.get('mac')
        server = data.get('server')
        if mac and server:
            channels = fetch_stalker_channels(mac, server)

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

def fetch_xtream_channels(username, password, server):
    try:
        url = f"{server}/player_api.php?username={username}&password={password}&action=get_live_streams"
        response = requests.get(url)
        if response.status_code == 200:
            data = response.json()
            return [{"name": stream['name'], "url": stream['stream_url']} for stream in data]
    except Exception as e:
        print(f"Error fetching Xtream channels: {e}")
        return []

def fetch_stalker_channels(mac, server):
    try:
        url = f"{server}/server/load.php?type=stb&action=get_profile&mac={mac}"
        response = requests.get(url)
        if response.status_code == 200:
            data = response.json()
            return [{"name": channel['name'], "url": channel['url']} for channel in data['channels']]
    except Exception as e:
        print(f"Error fetching Stalker channels: {e}")
        return []

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
