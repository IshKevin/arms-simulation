"""Minimal Flask service used to validate multi-service CI/CD detection."""
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
    return jsonify(message="hello from timeservice")


@app.route("/time")
def current_time():
    """Report the current UTC time."""
    return jsonify(utc_time=datetime.now(timezone.utc).isoformat())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
