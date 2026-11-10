# Environment to build and test restv2: ROOT, Geant4, Garfield++, CRY, prometheus-cpp, yaml-cpp and GoogleTest.
# The versions are build arguments (see README.md). The environment is static (ENV, as the image
# lobis/docker-root-geant4-garfield): no setup script is sourced (thisroot.sh, geant4.sh run other bash
# scripts, which with BASH_ENV sourced the environment again, endlessly). Only the paths of the Geant4 datasets,
# known after its installation, are in /opt/geant4-datasets.sh (plain exports, written from
# `geant4-config --datasets`), sourced by every bash shell (BASH_ENV for non-interactive shells such as the
# steps of GitHub Actions, /etc/bash.bashrc for interactive ones).

FROM ubuntu:24.04

ARG ROOT_VERSION=6.36.04
ARG GEANT4_VERSION=11.0.3
ARG GARFIELD_VERSION=4.0
ARG CRY_VERSION=1.7
ARG PROMETHEUS_VERSION=1.2.4
ARG JOBS=4

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System packages: compilers and tools, the dependencies of the ROOT binary (X11, OpenGL, TBB, VDT,
# compression, GSL, FFTW, XML...), Xerces-C (GDML of Geant4), GSL and gfortran (Garfield++), and the
# dependencies of restv2 (yaml-cpp, GoogleTest, readline for restDAQ, ccache, Doxygen)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gfortran cmake ninja-build git ca-certificates curl wget file \
        python3 python3-dev python3-numpy libssl-dev \
        libx11-dev libxext-dev libxft-dev libxpm-dev libxmu-dev libxi-dev \
        libgl-dev libglu1-mesa-dev libglew-dev libftgl-dev libgl2ps-dev \
        libtbb-dev libvdt-dev libgif-dev libjpeg-dev libpng-dev libtiff-dev \
        libfftw3-dev libgsl-dev libxml2-dev libpcre3-dev libpcre2-dev libcfitsio-dev \
        libxxhash-dev libzstd-dev liblz4-dev liblzma-dev zlib1g-dev nlohmann-json3-dev \
        libxerces-c-dev libexpat1-dev libcurl4-openssl-dev \
        libyaml-cpp-dev libgtest-dev libgmock-dev libreadline-dev \
        ccache doxygen graphviz \
    && rm -rf /var/lib/apt/lists/*

# Environment of ROOT (what thisroot.sh sets for restv2), Geant4, Garfield++ and CRY, installed below in /opt
ENV ROOTSYS=/opt/root \
    GARFIELD_INSTALL=/opt/garfield \
    HEED_DATABASE=/opt/garfield/share/Heed/database \
    CRYHOME=/opt/cry \
    CRYDATAPATH=/opt/cry/data
ENV PATH=/opt/root/bin:/opt/geant4/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/root/lib:/opt/geant4/lib:/opt/garfield/lib \
    PYTHONPATH=/opt/root/lib \
    ROOT_INCLUDE_PATH=/opt/garfield/include \
    CMAKE_PREFIX_PATH=/opt/root:/opt/geant4:/opt/garfield
# Paths of the Geant4 datasets: empty until Geant4 is installed
RUN touch /opt/geant4-datasets.sh && echo "source /opt/geant4-datasets.sh" >> /etc/bash.bashrc
ENV BASH_ENV=/opt/geant4-datasets.sh

# ROOT: official binary for Ubuntu 24.04 (with TMVA, RooFit, Eve/OpenGL, GDML); the build fails if a library
# used by restv2 misses a system dependency
RUN curl -fsSL "https://root.cern/download/root_v${ROOT_VERSION}.Linux-ubuntu24.04-x86_64-gcc13.3.tar.gz" \
        | tar -xz -C /opt \
    && missing=$(ldd /opt/root/lib/lib{Core,RIO,Tree,Hist,Geom,Gdml,Gui,Eve,RGL,TreePlayer,ROOTDataFrame,RooFitCore,RooFit,TMVA}.so \
        | grep "not found" | sort -u || true) \
    && if [ -n "$missing" ]; then echo "ROOT: missing libraries:"; echo "$missing"; exit 1; fi \
    && root-config --version

# Geant4 with GDML, multithreading and its data, from its GitHub mirror (gitlab.cern.ch resets connections),
# retried. The paths of the datasets are written to /opt/geant4-datasets.sh. Geant4 11.0 uses
# std::uint32_t/uint64_t without including <cstdint> (CLHEP), which GCC >= 13 no longer includes through other
# headers: included in every file of the build, and added to the installed headers that need it (used by
# restG4). EXPAT_LIBRARY given explicitly: with CMake >= 3.27 FindEXPAT sets only EXPAT_LIBRARY_RELEASE, and
# Geant4 11.0 writes an empty EXPAT_LIBRARY to Geant4PackageCache.cmake, which breaks find_package(Geant4)
RUN for attempt in 1 2 3 4 5; do \
        git clone --depth 1 --branch "v${GEANT4_VERSION}" https://github.com/Geant4/geant4.git /tmp/geant4 \
        && break; rm -rf /tmp/geant4; sleep 60; done \
    && test -d /tmp/geant4 \
    && cmake -S /tmp/geant4 -B /tmp/geant4-build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/geant4 \
        -DGEANT4_USE_GDML=ON -DGEANT4_INSTALL_DATA=ON -DGEANT4_BUILD_MULTITHREADED=ON \
        -DGEANT4_USE_SYSTEM_EXPAT=ON -DEXPAT_LIBRARY=/usr/lib/x86_64-linux-gnu/libexpat.so \
        -DGEANT4_USE_OPENGL_X11=ON -DCMAKE_CXX_FLAGS="-include cstdint" \
    && cmake --build /tmp/geant4-build -j "${JOBS}" \
    && cmake --install /tmp/geant4-build \
    && ! grep -n '_LIBRARY ""' /opt/geant4/lib/Geant4-*/Geant4PackageCache.cmake \
    && { grep -rlE '\b(std::)?u?int(8|16|32|64)_t\b' /opt/geant4/include | xargs -r grep -L '<cstdint>' \
         | xargs -r sed -i '1i #include <cstdint>' || true; } \
    && rm -rf /tmp/geant4 /tmp/geant4-build \
    && geant4-config --datasets | awk 'NF == 3 { print "export " $2 "=" $3 }' > /opt/geant4-datasets.sh \
    && cat /opt/geant4-datasets.sh && test -s /opt/geant4-datasets.sh \
    && geant4-config --version

# Garfield++ (needs ROOT, GSL and gfortran): cloned from gitlab.cern.ch, retried. Local backup: if the clone
# fails and garfieldpp-<version>.tar.gz is in the build directory (a copy made where gitlab.cern.ch is
# reachable, not in the repository), it is used without retrying. .dockerignore is copied with it only so that
# the COPY does not fail without tarball (not the Dockerfile: any change of it would rebuild Garfield++).
# <cstdint> included in every file as for Geant4 (GCC >= 13). Built with Makefiles: Ninja passes the Fortran of
# Magboltz through the C preprocessor, which takes the continuation lines starting with "/**" for unterminated
# C comments
COPY .dockerignore garfieldpp-*.tar.gz /tmp/garfield-src/
RUN backup="/tmp/garfield-src/garfieldpp-${GARFIELD_VERSION}.tar.gz" \
    && for attempt in 1 2 3 4 5; do \
           git clone --depth 1 --branch "${GARFIELD_VERSION}" https://gitlab.cern.ch/garfield/garfieldpp.git \
               /tmp/garfield && break; rm -rf /tmp/garfield; [ -f "$backup" ] && break; sleep 60; done \
    && if [ ! -d /tmp/garfield ] && [ -f "$backup" ]; then \
           echo "Garfield++: gitlab.cern.ch not reachable, using $backup"; \
           mkdir /tmp/garfield && tar -xzf "$backup" -C /tmp/garfield --strip-components=1; \
       fi \
    && rm -rf /tmp/garfield-src \
    && test -d /tmp/garfield \
    && cmake -S /tmp/garfield -B /tmp/garfield-build \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/garfield -DWITH_EXAMPLES=OFF \
        -DCMAKE_CXX_FLAGS="-include cstdint" \
    && cmake --build /tmp/garfield-build -j "${JOBS}" \
    && cmake --install /tmp/garfield-build \
    && { grep -rlE '\b(std::)?u?int(8|16|32|64)_t\b' /opt/garfield/include | xargs -r grep -L '<cstdint>' \
         | xargs -r sed -i '1i #include <cstdint>' || true; } \
    && mkdir -p /opt/garfield/share/Heed \
    && if [ ! -d /opt/garfield/share/Heed/database ]; then \
           cp -r /tmp/garfield/Heed/heed++/database /opt/garfield/share/Heed/database; \
       fi \
    && rm -rf /tmp/garfield /tmp/garfield-build

# CRY (static library, headers in src/ and tables in data/)
RUN curl -fsSL "https://nuclear.llnl.gov/simulation/cry_v${CRY_VERSION}.tar.gz" | tar -xz -C /tmp \
    && mv "/tmp/cry_v${CRY_VERSION}" /opt/cry \
    && make -C /opt/cry \
    && test -f /opt/cry/lib/libCRY.a

# prometheus-cpp (restDAQ), without push (as restDAQ downloads it)
RUN git clone --depth 1 --branch "v${PROMETHEUS_VERSION}" --recurse-submodules \
        https://github.com/jupp0r/prometheus-cpp.git /tmp/prometheus-cpp \
    && cmake -S /tmp/prometheus-cpp -B /tmp/prometheus-cpp-build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DENABLE_PUSH=OFF -DENABLE_TESTING=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    && cmake --build /tmp/prometheus-cpp-build -j "${JOBS}" \
    && cmake --install /tmp/prometheus-cpp-build \
    && rm -rf /tmp/prometheus-cpp /tmp/prometheus-cpp-build

WORKDIR /work
CMD ["/bin/bash"]
