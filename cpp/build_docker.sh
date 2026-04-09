#! /bin/sh

docker run -v "$(pwd)":/src -w /src ghcr.io/webassembly/wasi-sdk make -j"$(nproc)"
