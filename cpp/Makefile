.DEFAULT_GOAL := all
# NOTE: wasi-libc++ and wasi-libc++abi must be installed separately
OUTDIR=./build/wasm
PROCESSORS_OUTDIR=$(OUTDIR)/processors
LIBCLANG_RUNTIME=/usr/lib/clang/21/lib/wasi/libclang_rt.builtins-wasm32.a

CC_FLAGS=\
				 -std=c++20 \
				 -fno-exceptions \
				 -Wall \
				 -Wextra \
				 -O2 \
				 --target=wasm32-wasi \
				 --sysroot=/usr/share/wasi-sysroot \
				 -stdlib=libc++\
				 -Iinclude\
				 # /usr/lib/clang/21/lib/wasi/libclang_rt.builtins-wasm32.a\

LD_FLAGS=\
				 --no-entry \
				 --import-undefined \
     		 -L/usr/share/wasi-sysroot/lib/wasm32-wasi/ \
				 -lc++\
				 -lc++abi \
				 -lc \
				 -export="malloc"\

%.o: %.cpp
	clang++ $(CC_FLAGS) $^ -c -o $@

$(PROCESSORS_OUTDIR)/%.wasm: processors/%.o wasm_helpers.o
	mkdir -p $(PROCESSORS_OUTDIR)
	wasm-ld $(LIBCLANG_RUNTIME) $^ -o $@ $(LD_FLAGS)

PROCESSORS_SRC=$(wildcard processors/*.cpp)
PROCESSORS_WASM=$(addprefix $(OUTDIR)/, $(PROCESSORS_SRC:.cpp=.wasm))

all: $(PROCESSORS_WASM)

.PHONY: all
