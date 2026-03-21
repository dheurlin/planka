#include <cstddef>
#include <cstring>
#include <string>

#include "vendor/simple_fft/fft_settings.h"
#include "vendor/simple_fft/fft.h"

#include "wasm_helpers.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output channels have this length
const unsigned FRAME_SIZE = 128;

class PitchShiftProcessor {
public:
  PitchShiftProcessor(): m_frame_count(0), m_fft_error(new char[512])
    {

    console::log("PitchShiftProcessor initialised!");
    console::error("Error test!");

  }

  bool process(
    float *input_channels,
    unsigned input_num_channels,
    float *output_channels,
    unsigned output_num_channels
  ) {
    (void) output_num_channels;
    for (unsigned input_channel = 0; input_channel < input_num_channels; input_channel++) {
      std::vector<std::complex<float>> fft_out(FRAME_SIZE);

      auto error = m_fft_error.get();
      auto ok = simple_fft::FFT(&input_channels[input_channel * FRAME_SIZE], fft_out, FRAME_SIZE, error);

      if (!ok) {
        console::error("FFT Failed with the following:");
        console::error(m_fft_error.get());
        return false;
      } 

      ok = simple_fft::IFFT(fft_out, FRAME_SIZE, error);
      if (!ok) {
        console::error("IFFT Failed with the following:");
        console::error(m_fft_error.get());
        return false;
      }

      std::unique_ptr<float> ifft_out_real(new float[FRAME_SIZE]);
      std::transform(fft_out.cbegin(), fft_out.cend(), ifft_out_real.get(), [](std::complex<float> c) {
        return c.real();
      });

      std::memcpy(&output_channels[input_channel * FRAME_SIZE], ifft_out_real.get(), FRAME_SIZE * sizeof(*output_channels));
    }

    m_frame_count++;
    return true;
  }

private:
  unsigned m_frame_count;
  std::unique_ptr<const char> m_fft_error;
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
  unsigned input_num_channels,
  float *output_channels,
  unsigned output_num_channels
) {
  return self->process(input_channels, input_num_channels, output_channels, output_num_channels);
}
