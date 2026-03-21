#include <cstddef>
#include <cstring>
#include <string>

#include "wasm_helpers.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output channels have this length
const unsigned FRAME_SIZE = 128;

class PitchShiftProcessor {
public:
  PitchShiftProcessor()
    {

    console::log("PitchShiftProcessor initialised!");
  }

  bool process(
    float *input_channels,
    int input_num_channels,
    float *output_channels,
    int output_num_channels
  ) {
    (void) input_num_channels;
    std::memcpy(output_channels, input_channels, output_num_channels * FRAME_SIZE * sizeof(*output_channels));
    return true;
  }

private:
};

WASM_EXPORT(PitchShiftProcessor_init)
PitchShiftProcessor* PitchShiftProcessor_init() {
  // We only expect there to be one instance, so should be fine memory-wise??
  return new PitchShiftProcessor();
}

WASM_EXPORT(PitchShiftProcessor_process)
bool PitchShiftProcessor_process(
  PitchShiftProcessor *self,
  float *input_channels,
  int input_num_channels,
  float *output_channels,
  int output_num_channels
) {
  return self->process(input_channels, input_num_channels, output_channels, output_num_channels);
}
