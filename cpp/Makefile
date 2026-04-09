.DEFAULT_GOAL := all

# Note: WASI_SDK https://github.com/WebAssembly/wasi-sdk must be installed to build

WASI_SDK_PATH=/opt/wasi-sdk
CC="${WASI_SDK_PATH}/bin/clang++"

OUTDIR=./build/wasm
PROCESSORS_OUTDIR=$(OUTDIR)/processors
CPP_DEPS=./vendor/StftPitchShift/StftPitchShift.cpp
CPP_DEPS_O=$(CPP_DEPS:.cpp=.o)

CC_FLAGS=\
	-std=c++20 \
	-fno-exceptions \
	-Wall \
	-Wextra \
	-O3 \
	-Iinclude \
	-Ivendor \

%.o: %.cpp
	$(CC) $(CC_FLAGS) $^ -c -o $@

$(PROCESSORS_OUTDIR)/%.wasm: processors/%.o wasm_helpers.o $(CPP_DEPS_O)
	mkdir -p $(PROCESSORS_OUTDIR)
	$(CC) $^ -o $@ -Wl,--import-undefined -Wl,-export="malloc" 

PROCESSORS_SRC=$(wildcard processors/*.cpp)
PROCESSORS_WASM=$(addprefix $(OUTDIR)/, $(PROCESSORS_SRC:.cpp=.wasm))

all: $(PROCESSORS_WASM)

.PHONY: all
