FROM ubuntu:20.04

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install basic build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    ninja-build \
    git \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install newer CMake for ARM64
RUN CMAKE_VERSION="3.25.3" \
    && wget -O cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-aarch64.tar.gz" \
    && tar -xzf cmake.tar.gz -C /opt \
    && ln -sf /opt/cmake-${CMAKE_VERSION}-linux-aarch64/bin/* /usr/local/bin/ \
    && rm cmake.tar.gz \
    && cmake --version

# Set working directory
WORKDIR /workspace

# Create build directories
RUN mkdir -p dist build install

# Default command
CMD ["/bin/bash"]