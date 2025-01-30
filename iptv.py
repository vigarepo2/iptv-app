from flask import Flask, request, jsonify, send_from_directory

app = Flask(__name__)

HTML_CONTENT = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV Player</title>
    <script>
        function loadStream(type, data) {
            fetch('/play', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: type, ...data })
            })
            .then(response => response.json())
            .then(data => {
                if (data.stream_url) {
                    let video = document.getElementById('video');
                    if (Hls.isSupported()) {
                        let hls = new Hls();
                        hls.loadSource(data.stream_url);
                        hls.attachMedia(video);
                    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                        video.src = data.stream_url;
                    }
                } else {
                    alert("Invalid IPTV source!");
                }
            });
        }

        function loadDirect() {
            let url = document.getElementById("direct-url").value;
            loadStream("direct", { url: url });
        }

        function uploadM3U() {
            let fileInput = document.getElementById("m3u-file");
            let file = fileInput.files[0];

            let formData = new FormData();
            formData.append("file", file);

            fetch('/upload', { method: 'POST', body: formData })
            .then(response => response.json())
            .then(data => {
                if (data.filename) {
                    loadStream("m3u", { filename: data.filename });
                } else {
                    alert("File upload failed!");
                }
            });
        }

        function loadXtream() {
            let server = document.getElementById("xtream-server").value;
            let username = document.getElementById("xtream-user").value;
            let password = document.getElementById("xtream-pass").value;
            loadStream("xtream", { server: server, username: username, password: password });
        }

        function loadStalker() {
            let portal = document.getElementById("stalker-portal").value;
            let mac = document.getElementById("stalker-mac").value;
            loadStream("stalker", { portal: portal, mac: mac });
        }
    </script>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</head>
<body>
    <h1>IPTV Player</h1>

    <h2>Play Direct IPTV Link</h2>
    <input type="text" id="direct-url" placeholder="Enter IPTV URL">
    <button onclick="loadDirect()">Play</button>

    <h2>Upload M3U File</h2>
    <input type="file" id="m3u-file">
    <button onclick="uploadM3U()">Upload & Play</button>

    <h2>Xtream Codes</h2>
    <input type="text" id="xtream-server" placeholder="Server URL">
    <input type="text" id="xtream-user" placeholder="Username">
    <input type="text" id="xtream-pass" placeholder="Password">
    <button onclick="loadXtream()">Play</button>

    <h2>Stalker Portal</h2>
    <input type="text" id="stalker-portal" placeholder="Portal URL">
    <input type="text" id="stalker-mac" placeholder="MAC Address">
    <button onclick="loadStalker()">Play</button>

    <video id="video" controls width="640" height="360"></video>
</body>
</html>
"""

import os
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/')
def index():
    return HTML_CONTENT

@app.route('/play', methods=['POST'])
def play():
    data = request.json
    source_type = data.get('type')
    stream_url = None

    if source_type == "direct":
        stream_url = data.get('url')
    
    elif source_type == "m3u":
        file_path = os.path.join(UPLOAD_FOLDER, data.get('filename'))
        if os.path.exists(file_path):
            stream_url = f"/uploads/{data.get('filename')}"
    
    elif source_type == "xtream":
        xtream_url = data.get('server')
        username = data.get('username')
        password = data.get('password')
        stream_url = f"{xtream_url}/live/{username}/{password}/"

    elif source_type == "stalker":
        portal = data.get('portal')
        mac = data.get('mac')
        stream_url = f"{portal}/c/{mac}"

    if not stream_url:
        return jsonify({'error': 'Invalid IPTV source'}), 400

    return jsonify({'stream_url': stream_url})

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    file_path = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(file_path)

    return jsonify({'filename': file.filename})

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(UPLOAD_FOLDER, filename)

if __name__ == '__main__':
    app.run(debug=True)
