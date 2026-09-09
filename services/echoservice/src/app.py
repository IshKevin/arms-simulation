"""Minimal Flask service used to validate multi-service CI/CD detection."""
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify(status="ok")


@app.route("/")
def index():
    """Root endpoint."""
    return jsonify(message="hello from echoservice disply")


@app.route("/ping")
def ping():
    """Simple liveness-style endpoint."""
    return jsonify(reply="pong")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
