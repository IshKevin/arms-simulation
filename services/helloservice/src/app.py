"""Minimal Flask service used to validate the ARMS CI/CD pipeline."""
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify(status="ok")


@app.route("/")
def index():
    """Root endpoint."""
    return jsonify(message="hello from helloservice")


@app.route("/version")
def version():
    """Report the current service version."""
    return jsonify(version="1.1.1")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
