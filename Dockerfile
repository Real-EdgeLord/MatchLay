FROM python:3.12-slim

# Install system dependencies for pyenet
RUN apt-get update && apt-get install -y --no-install-recommends \
    libenet-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all Python files
COPY main.py .
COPY enet_relay.py .
COPY static ./static

CMD ["python", "main.py"]
