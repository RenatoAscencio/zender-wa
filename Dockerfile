# -----------------------------------------------------------------------------
# WhatsApp Server Docker Image
#
# Author: @RenatoAscencio
# Repository: https://github.com/RenatoAscencio/zender-wa
# -----------------------------------------------------------------------------

# Use Ubuntu 22.04 as the base system
FROM ubuntu:22.04

# --- Build-time Arguments and Environment Variables ---
# These arguments are passed during the build process by GitHub Actions
ARG BUILD_DATE
ARG VERSION

# These environment variables make the build arguments available inside the container
ENV BUILD_DATE=$BUILD_DATE
ENV VERSION=$VERSION

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set the working directory. This MUST be an absolute path.
WORKDIR /data/whatsapp-server

# Install dependencies and clean up
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron curl unzip procps ca-certificates nano && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the main entrypoint script
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Declare the volume that will be used for persistent data.
VOLUME /data/whatsapp-server

# Expose the port
EXPOSE 443

# The command that will run when the container starts
ENTRYPOINT ["entrypoint.sh"]
