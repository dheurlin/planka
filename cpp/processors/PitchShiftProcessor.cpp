#include <array>
#include <cstddef>
#include <cstring>
#include <string>

#include "vendor/simple_fft/fft.h"

#include "wasm_helpers.h"
#include "utils.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output channels have this length
const unsigned FRAME_SIZE = 128;
const unsigned FRAMES_PER_BUFFER = 8;
const unsigned BUFFER_SIZE = FRAME_SIZE * FRAMES_PER_BUFFER;

// const float PITCH_SHIFT_FACTOR = std::pow(2, 4/12);
const float PITCH_SHIFT_FACTOR = 2;

class PitchShiftProcessor {
public:
  PitchShiftProcessor(): m_frame_count(0), m_fft_error(new char[512]), m_input_channels_buffer(0) {
    console::log("PitchShiftProcessor initialised!");
  }

  bool process(
    float *input_channels,
    unsigned input_num_channels,
    float *output_channels,
    unsigned output_num_channels
  ) {
    // Initialize the buffers if needed
    if (m_input_channels_buffer.size() == 0) {
      for (unsigned i = 0; i < input_num_channels; i++) {
        m_input_channels_buffer.push_back({0});
        m_input_phases.push_back({0});
        m_output_phases.push_back({0});
      }
    }
    (void) output_num_channels;
    for (unsigned input_channel = 0; input_channel < input_num_channels; input_channel++) {
      // Shift the new sample into the buffer
      auto buffer_start = m_input_channels_buffer[input_channel].data();
      auto input_start = &input_channels[input_channel * FRAME_SIZE];

      std::memmove(buffer_start, buffer_start + FRAME_SIZE, sizeof(float) * (BUFFER_SIZE - FRAME_SIZE));
      std::memcpy(buffer_start + (BUFFER_SIZE - FRAME_SIZE), input_start, sizeof(float) * FRAME_SIZE);
  
      std::vector<std::complex<float>> fft_out(BUFFER_SIZE);

      auto error = m_fft_error.get();
      auto ok = simple_fft::FFT(buffer_start, fft_out, BUFFER_SIZE, error);

      if (!ok) {
        console::error("FFT Failed with the following:");
        console::error(m_fft_error.get());
        return false;
      } 

      auto transformed = pitch_shift(
        fft_out,
        m_input_phases[input_channel].data(),
        m_output_phases[input_channel].data()
      );

      if (transformed.size() != fft_out.size()) {
        console::error("Transformed size: " + s(transformed.size()));
        console::error("FFT Output size: " + s(fft_out.size()));
      }
      browser_assert(transformed.size() == fft_out.size() && "Output should have same size!");

      ok = simple_fft::IFFT(transformed, BUFFER_SIZE, error);
      if (!ok) {
        console::error("IFFT Failed with the following:");
        console::error(m_fft_error.get());
        return false;
      }

      std::unique_ptr<float> ifft_out_real(new float[BUFFER_SIZE]);
      std::transform(transformed.cbegin(), transformed.cend(), ifft_out_real.get(), [](std::complex<float> c) {
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
  std::vector<std::array<float, BUFFER_SIZE>> m_input_channels_buffer;
  std::vector<std::array<float, BUFFER_SIZE>> m_input_phases;
  std::vector<std::array<float, BUFFER_SIZE>> m_output_phases;

  // This algorithm is based on https://csg.csail.mit.edu/6.375/6_375_2016_www/handouts/labs
  // I don't fully understand how it works
  std::vector<std::complex<float>> pitch_shift(
    std::vector<std::complex<float>> &input,
    float* input_phases,
    float* output_phases
  ) {
    std::vector<std::complex<float>> output(BUFFER_SIZE, 0);
    for (unsigned i = 0; i < BUFFER_SIZE; i++) {
      utils::complexMP mp(input[i]);
      auto phase_diff = mp.phase() - input_phases[i];
      input_phases[i] = mp.phase();

      unsigned target_bin = i * PITCH_SHIFT_FACTOR;
      if (target_bin > BUFFER_SIZE || target_bin < 0) {
        continue;
      }

      auto shifted = phase_diff * PITCH_SHIFT_FACTOR;
      output_phases[target_bin] += shifted;
      utils::complexMP mp_shifted(mp);
      mp_shifted.set_phase(output_phases[target_bin]);

      output[target_bin] = mp_shifted.to_complex();
      // output.push_back(mp_shifted.to_complex());
    }

    return output;
  }
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
