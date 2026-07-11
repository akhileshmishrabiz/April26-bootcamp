FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# ClamAV paths for Ubuntu 22.04 (used by scanner via env without changing Python defaults)
ENV DATABASE_DIRECTORY=/var/lib/clamav

# Update and install dependencies
RUN apt-get update && apt-get install -y \
    clamav \
    clamav-daemon \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Create ClamAV directories with correct ownership
RUN mkdir -p /var/lib/clamav /var/log/clamav /var/run/clamav \
    && chown -R clamav:clamav /var/lib/clamav /var/log/clamav /var/run/clamav

# Copy custom ClamAV configs before running freshclam
COPY config/freshclam.conf /etc/clamav/freshclam.conf
COPY config/clamd.conf /etc/clamav/clamd.conf
RUN chown clamav:clamav /etc/clamav/freshclam.conf /etc/clamav/clamd.conf \
    && chmod 644 /etc/clamav/freshclam.conf /etc/clamav/clamd.conf

# Seed virus database at build time
RUN freshclam

# Set working directory
WORKDIR /app

# Copy requirements file
COPY scanner/requirements.txt .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy the application
COPY scanner .

# Run the script
CMD ["python3", "main.py", "--action", "scan"]
