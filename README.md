# rest-docker

Docker image with the environment to build and test rest-for-physics-toolkit: ROOT, Geant4, Garfield++,
CRY, prometheus-cpp, yaml-cpp and GoogleTest. It is used by the validation workflow of rest-framework (GitHub
Actions), and can be used to build rest-for-physics-toolkit locally in a clean environment.

| Software | Version | Installed in |
|---|---|---|
| Ubuntu | 24.04 (GCC 13, CMake 3.28) | |
| ROOT | 6.36.04 (official binary for Ubuntu 24.04: TMVA, RooFit, Eve/OpenGL, GDML) | `/opt/root` |
| Geant4 | 11.0.3 (GDML, multithreaded, with its data) | `/opt/geant4` |
| Garfield++ | 4.0 | `/opt/garfield` (`GARFIELD_INSTALL`) |
| CRY | 1.7 | `/opt/cry` (`CRYHOME`) |
| prometheus-cpp | 1.2.4 (no push) | `/usr/local` |
| yaml-cpp, GoogleTest, readline, ccache, Doxygen | Ubuntu packages | `/usr` |

The environment of all of them is static (`ENV` of the Dockerfile: `ROOTSYS`, `PATH`, `LD_LIBRARY_PATH`,
`CMAKE_PREFIX_PATH`, `GARFIELD_INSTALL`, `HEED_DATABASE`, `CRYHOME`...), as in the image
[lobis/docker-root-geant4-garfield](https://github.com/lobis/docker-root-geant4-garfield): no setup script
(thisroot.sh, geant4.sh) is sourced. Only the paths of the Geant4 datasets are in `/opt/geant4-datasets.sh`
(plain exports written from `geant4-config --datasets`), sourced by every bash shell: through `BASH_ENV` for
non-interactive shells (the `run` steps of GitHub Actions, `docker run ... bash -c`) and `/etc/bash.bashrc`
for interactive ones. Geant4 is cloned from its GitHub mirror and Garfield++ from gitlab.cern.ch, with
retries. As a local backup (not in the repository), if the clone fails and a copy made elsewhere (e.g. in
lxplus) is in this directory as `garfieldpp-<version>.tar.gz`, it is used (the repository in a top directory, e.g.
`git clone --depth 1 --branch 4.0 https://gitlab.cern.ch/garfield/garfieldpp.git garfieldpp && tar -czf garfieldpp-4.0.tar.gz garfieldpp`).

The versions are build arguments: `ROOT_VERSION` (the ROOT binary must exist for Ubuntu 24.04 in
https://root.cern/download), `GEANT4_VERSION`, `GARFIELD_VERSION` (a tag of the Garfield++ repository),
`CRY_VERSION`, `PROMETHEUS_VERSION`, and `JOBS` (parallel compilation).

## Build locally

```bash
cd rest-docker
docker build -t rest-env .                       # about 1 h (Geant4) and ~10 GB
docker build -t rest-env --build-arg JOBS=16 .   # faster on a machine with more cores
```

Check the image:

```bash
docker run --rm rest-env bash -c "root-config --version; geant4-config --version; echo \$GARFIELD_INSTALL \$CRYHOME"
```

Build and test rest-for-physics-toolkit with it (the repository mounted in `/work`; the build directory inside
the container):

```bash
docker run --rm -v /path/to/rest-framework:/work rest-env bash -c \
    "cmake -S /work -B /tmp/build -DBUILD_TESTING=ON -DREST_DAQ=ON && cmake --build /tmp/build -j8 && cd /tmp/build && ctest --output-on-failure"
```

## Publish in GitHub (ghcr.io)

1. Create a repository for this directory in your GitHub account or organization and push it
   (`git init`, `git add .`, `git commit`, `git remote add origin ...`, `git push -u origin master`).
2. The workflow `.github/workflows/build.yml` builds the image and publishes it as
   `ghcr.io/<owner>/rest-env` (owner in lowercase) at each push to `master` (tag `latest`) and each tag
   `v*` (e.g. `git tag v1 && git push origin v1`: tag `v1`), also with the commit (`sha-<hash>`). It can also
   be launched by hand (Actions, Build image, Run workflow). It takes about 1 h.
3. The package is private by default: to use it from the workflows of other repositories, in the package
   settings (your profile or organization, Packages, rest-env, Package settings) either make it public or
   give access to the rest-framework repository (Manage Actions access).

To publish a local build by hand instead:

```bash
echo <token with write:packages> | docker login ghcr.io -u <user> --password-stdin
docker tag rest-env ghcr.io/<owner>/rest-env:latest
docker push ghcr.io/<owner>/rest-env:latest
```

## Use in rest-framework

The validation workflow of rest-framework runs its jobs in the container `ghcr.io/<owner>/rest-env` (the owner
of the rest-framework repository, so both repositories must be in the same account or organization; otherwise
change the image name in the workflow).

## Updating the versions

Change the default of the build argument in the `Dockerfile`, push and tag a new version (e.g. `v2`). If
another version of ROOT, Geant4 or Garfield++ is not compatible with rest-for-physics-toolkit, fix
rest-framework before moving the `latest` tag used by its workflow.

## Image with rest-for-physics-toolkit installed (rest)

`rest/Dockerfile` builds rest-for-physics-toolkit on `rest-env` and installs it in `/opt/rest`, with its
environment set (`PATH`, `LD_LIBRARY_PATH`, `ROOT_INCLUDE_PATH`, `REST_PATH`): `restManager`, `restG4`,
`restRoot`... run directly, without building rest-for-physics-toolkit. Its build context is a clone of
rest-framework, so it is not built by this repository: the validation workflow of rest-framework builds it
with this Dockerfile and publishes it as `ghcr.io/<owner>/rest` when its tests pass, at each push to `master`
(tag `latest`, always in sync with `master`) and each release (its tag, e.g. `v1.0`), also with the commit
(`sha-<hash>`). It is used by the CI of the projects and of rest-common-readouts, and in a cluster with
Apptainer:

```bash
apptainer pull rest.sif docker://ghcr.io/<owner>/rest:v1.0
apptainer exec rest.sif restManager --config Analysis.yaml
```

Build it locally (from the directory above both clones; `build/` and `install/` of the clone are ignored,
`rest/Dockerfile.dockerignore`):

```bash
docker build -f rest-docker/rest/Dockerfile -t rest --build-arg JOBS=16 rest-framework
docker run --rm -v "$PWD":/work rest restManager --config config.yaml
```

As `rest-env`, the package is private by default: give access to the repositories that use it (Package
settings, Manage Actions access) or make it public. A new `rest-env` (e.g. another Geant4) reaches the `rest`
image at the next push to `master` of rest-framework (or running its validation by hand).
