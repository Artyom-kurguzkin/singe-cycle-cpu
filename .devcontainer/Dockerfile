FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Build + runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ca-certificates curl xz-utils make sudo \
    build-essential clang \
    bison flex libreadline-dev gawk tcl-dev libffi-dev pkg-config \
    cmake ninja-build \
    libboost-all-dev libeigen3-dev \
    python3 python3-dev python3-pip pypy3 \
    python3-setuptools cython3 \
    python3-intervaltree python3-numpy python3-openpyxl \
    python3-ordered-set python3-parse python3-progressbar2 \
    python3-json5 python3-pytest python3-yaml \
    python3-pytest-runner python3-scipy python3-simplejson \
    python3-sympy python3-yapf \
    default-jre-headless uuid-dev libantlr4-runtime-dev \
    libftdi1-2 libftdi1-dev libhidapi-hidraw0 libhidapi-dev \
    libudev-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ── OSS-CAD-Suite ──────────────────────────────────────────────────────────────
# Provides: yosys, ghdl, ghdl-yosys-plugin, openFPGALoader
# Does NOT include nextpnr-xilinx or prjxray (those are built below)
ARG OSS_CAD_DATE=2026-07-03
RUN cd /tmp \
 && wget -q "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_DATE}/oss-cad-suite-linux-x64-$(echo ${OSS_CAD_DATE} | tr -d '-').tgz" \
 && tar -xzf oss-cad-suite-linux-x64-*.tgz -C /opt \
 && rm oss-cad-suite-linux-x64-*.tgz

ENV PATH=/opt/oss-cad-suite/bin:${PATH}

# ── nextpnr-xilinx ─────────────────────────────────────────────────────────────
# Provides: nextpnr-xilinx, bbasm, bbaexport.py
ENV INSTALL_PREFIX=/opt/openxc7
ARG NEXTPNR_XILINX_HASH=f681eb3aa519f6ed41670dd8a4b39f87e9fb5498

RUN mkdir -p ${INSTALL_PREFIX}/lib/python ${INSTALL_PREFIX}/bin \
 && git clone https://github.com/openXC7/nextpnr-xilinx.git /tmp/nextpnr-xilinx \
 && cd /tmp/nextpnr-xilinx \
 && git checkout ${NEXTPNR_XILINX_HASH} \
 && git submodule update --init --recursive \
 && sed -i "s/foreach (PyVer 3 36 37 38 39 310 311 312)/foreach (PyVer 3 36 37 38 39 310 311 312 313)/g" CMakeLists.txt \
 && cmake -S . -B build \
          -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
          -DARCH=xilinx \
          -DUSE_OPENMP=ON \
          -DBUILD_GUI=OFF \
 && cmake --build build -j"$(nproc)" \
 && cmake --install build \
 && cp build/bbasm ${INSTALL_PREFIX}/bin/ \
 && cp xilinx/constids.inc ${INSTALL_PREFIX}/lib/ \
 && cp xilinx/constids.inc xilinx/python/* ${INSTALL_PREFIX}/lib/python/ \
 && cp -r xilinx/external ${INSTALL_PREFIX}/lib/external \
 && rm -rf /tmp/nextpnr-xilinx

# ── prjxray ────────────────────────────────────────────────────────────────────
# Provides: xc7frames2bit (C++ tool), fasm2frames (Python script via fasm pkg)
ARG PRJXRAY_HASH=ce065d470ea9547bba97b9df4476a0148e728c95

RUN git clone https://github.com/openXC7/prjxray.git /tmp/prjxray \
 && cd /tmp/prjxray \
 && git checkout ${PRJXRAY_HASH} \
 && git submodule update --init --recursive \
 && cmake -S . -B build -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
 && cmake --build build -j"$(nproc)" \
 && cmake --install build \
 && pip3 install -r requirements.txt \
 && pip3 install . \
 && cd third_party/fasm \
 && python3 setup.py install --antlr-runtime=shared --home=${INSTALL_PREFIX} \
 && rm -rf /tmp/prjxray

# ── prjxray-db ─────────────────────────────────────────────────────────────────
# Device fabric database for all 7-series parts (~600 MB)
ARG PRJXRAY_DB_TAG=0.8.2

RUN git clone --depth 1 --branch ${PRJXRAY_DB_TAG} \
      https://github.com/openXC7/prjxray-db.git /tmp/prjxray-db \
 && mkdir -p ${INSTALL_PREFIX}/share/nextpnr/prjxray-db \
 && cp -r /tmp/prjxray-db/* ${INSTALL_PREFIX}/share/nextpnr/prjxray-db/ \
 && rm -rf /tmp/prjxray-db

# ── Runtime environment ────────────────────────────────────────────────────────
ENV PATH=${INSTALL_PREFIX}/bin:${PATH} \
    PYTHONPATH=${INSTALL_PREFIX}/lib/python \
    NEXTPNR_XILINX_DIR=${INSTALL_PREFIX} \
    NEXTPNR_XILINX_PYTHON_DIR=${INSTALL_PREFIX}/lib/python \
    PRJXRAY_DB_DIR=${INSTALL_PREFIX}/share/nextpnr/prjxray-db \
    CHIPDB_DIR=${INSTALL_PREFIX}/share/nextpnr/chipdb \
    PYPY3=pypy3

# ── chipdb for xc7a100t ────────────────────────────────────────────────────────
# Generated once and cached in the image (several minutes, needs ~2 GB RAM)
RUN mkdir -p ${CHIPDB_DIR} \
 && pypy3 ${NEXTPNR_XILINX_PYTHON_DIR}/bbaexport.py \
          --device xc7a100tcsg324-1 \
          --bba /tmp/xc7a100t.bba \
 && bbasm -l /tmp/xc7a100t.bba ${CHIPDB_DIR}/xc7a100t.bin \
 && rm /tmp/xc7a100t.bba

# ── Node.js 20 ─────────────────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ──────────────────────────────────────────────────────────────
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME

# ── Claude Code CLI ────────────────────────────────────────────────────────────
RUN mkdir -p /home/$USERNAME/.npm-global \
    && npm config set prefix /home/$USERNAME/.npm-global \
    && npm install -g @anthropic-ai/claude-code

ENV PATH="/home/${USERNAME}/.npm-global/bin:${PATH}"
WORKDIR /workspace
