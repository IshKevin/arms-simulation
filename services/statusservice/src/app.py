"""Minimal Flask service used to validate the fixed CI/CD pipeline."""
import time

from flask import Flask, jsonify

app = Flask(__name__)
START_TIME = time.time()


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify(status="ok")


@app.route("/")
def index():
    """Root endpoint."""
    return jsonify(message="hello from statusservice")


@app.route("/status")
def status():
    """Report uptime in seconds."""
    return jsonify(uptime_seconds=round(time.time() - START_TIME, 2))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
