"""Minimal Flask service used as a live demo of the ARMS CI/CD pipeline."""
from datetime import datetime, timezone

from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify(status="ok")


@app.route("/")
def index():
    """Root endpoint."""
    return jsonify(message="hello from demoservice")


@app.route("/info")
def info():
    """Report basic service metadata, useful for a live demo."""
    return jsonify(
        service="demoservice",
        version="1.0.0",
        server_time=datetime.now(timezone.utc).isoformat(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
