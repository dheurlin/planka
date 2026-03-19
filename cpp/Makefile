# NOTE: wasi-libc++ and wasi-libc++abi must be installed separately
OUTDIR=../dist/wasm
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


# LD_FLAGS=-Wl,--no-entry -Wl,--strip-all
LD_FLAGS=\
				 --no-entry \
				 --import-undefined \
     		 -L/usr/share/wasi-sysroot/lib/wasm32-wasi/ \
				 -lc++\
				 -lc++abi \
				 -lc \
				 -export="malloc"\

test.o: test.cpp
	clang++ $(CC_FLAGS) -c -o $@ $^

$(OUTDIR)/test.wasm: test.o
	mkdir -p $(OUTDIR)
	# clang++ $(CC_FLAGS) $(LD_FLAGS) -o $@ $^ -v
	wasm-ld $< -o $@ $(LD_FLAGS)

processors/PlaybackProcessor.o: processors/PlaybackProcessor.cpp
	clang++ $(CC_FLAGS) -c -o $@ $^

$(OUTDIR)/processors/PlaybackProcessor.wasm: processors/PlaybackProcessor.o
	mkdir -p $(OUTDIR)/processors/
	# clang++ $(CC_FLAGS) $(LD_FLAGS) -o $@ $^ -v
	wasm-ld $< -o $@ $(LD_FLAGS)

test: $(OUTDIR)/test.wasm
playback: $(OUTDIR)/processors/PlaybackProcessor.wasm

.PHONY: test
