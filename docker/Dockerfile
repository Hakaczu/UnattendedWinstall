FROM ubuntu:24.04

# Install required tools
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        xorriso \
        smbclient \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy entrypoint
COPY build-iso.sh /usr/local/bin/build-iso.sh
RUN chmod +x /usr/local/bin/build-iso.sh

# /repo   – mount the repository root (provides autounattend.xml)
# /input  – optional: mount a directory containing windows.iso to skip download
# /output – the built ISO is written here
VOLUME ["/repo", "/input", "/output"]

WORKDIR /tmp/iso-build

ENTRYPOINT ["/usr/local/bin/build-iso.sh"]
