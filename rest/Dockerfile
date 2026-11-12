# restv2 built and installed in /opt/rest on the environment image (rest-env, ../Dockerfile): ready to run
# restManager, restG4, restRoot... without building restv2. The build context is a clone of rest-framework
# (with its tags, for the version of restv2):
#   docker build -f rest-docker/rest/Dockerfile -t rest rest-framework
# Built and published by the validation workflow of rest-framework (ghcr.io/<owner>/rest) after its tests
# pass at each push to master (tag latest) and each release (tag of the release).
#
# The environment is static (ENV, what thisREST.sh sets), as that of rest-env: thisREST.sh is not sourced (it
# sources thisroot.sh, which runs other bash scripts, endless with BASH_ENV).

ARG BASE_IMAGE=ghcr.io/rest-for-physics-toolkit/rest-env:latest
FROM ${BASE_IMAGE}

ARG JOBS=4

COPY . /tmp/rest-framework
RUN cmake -S /tmp/rest-framework -B /tmp/rest-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/rest -DREST_DAQ=ON \
    && cmake --build /tmp/rest-build --target install -j "${JOBS}" \
    && rm -rf /tmp/rest-framework /tmp/rest-build

ENV REST_PATH=/opt/rest \
    PATH=/opt/rest/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/rest/lib:${LD_LIBRARY_PATH} \
    LIBRARY_PATH=/opt/rest/lib \
    ROOT_INCLUDE_PATH=/opt/rest/include:${ROOT_INCLUDE_PATH}

# Every application installed and the libraries loaded
RUN restRoot -b -q && command -v restManager restG4 restCRY restGarfield femclient

WORKDIR /work
CMD ["/bin/bash"]
