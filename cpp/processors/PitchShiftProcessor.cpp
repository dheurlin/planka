#include <cstddef>
#include <cstring>
#include <string>

#include "vendor/pitchshiftercpp/phasevocoder.hpp"

#include "wasm_helpers.h"
#include "SimpleFFTAdapter.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output frames have this length
const size_t FRAME_SIZE = 128;

constexpr float MAX_SHIFT_FACTOR = 1.5;
const unsigned PV_OVERLAP_FACTOR = 4;

// const float PITCH_SHIFT_FACTOR = 1.5;
const float PITCH_SHIFT_FACTOR = 1;

using pv_t = pv::PhaseVocoder<FRAME_SIZE,
    static_cast<uint32_t>(FRAME_SIZE * MAX_SHIFT_FACTOR),
    SimpleFFTAdapter, float>;


class PitchShiftProcessor {
public:
  PitchShiftProcessor(unsigned sample_rate):
    m_frame_count(0),
    m_sample_rate(sample_rate),
    m_fft_adapter(new SimpleFFTAdapter(FRAME_SIZE)) {
    console::log("PitchShiftProcessor initialised!");
    console::log("Sample rate: " + s(sample_rate));
  }

  bool process(
    float *input_channels,
    unsigned input_num_channels,
    float *output_channels,
    unsigned output_num_channels
  ) {
    (void) output_num_channels;
    (void) input_num_channels;
    ensure_vocoders_initialized(input_num_channels);

    for (unsigned channel = 0; channel < input_num_channels; channel++) {
      m_vocoders[channel].process(
        &input_channels[channel * FRAME_SIZE],
        &output_channels[channel * FRAME_SIZE],
        FRAME_SIZE,
        PITCH_SHIFT_FACTOR
      );
    }

    m_frame_count++;
    return true;
  }

private:
  unsigned m_frame_count;
  unsigned m_sample_rate;
  std::vector<pv_t> m_vocoders;
  std::unique_ptr<SimpleFFTAdapter> m_fft_adapter;

  void ensure_vocoders_initialized(unsigned num_channels) {
    auto existing_channels = m_vocoders.size();
    if (existing_channels > 0) {
      if (existing_channels != num_channels) {
        console::error("Vocoders already initialised with " + s(m_vocoders.size()) + " channels");
        browser_assert(false && "Vocoder error");
      } else {
        // All good, nothing to do
        return;
      }
    }
    for (unsigned i = 0; i < num_channels; i++) {
      m_vocoders.emplace_back(*m_fft_adapter, PV_OVERLAP_FACTOR);
    }
    console::log("Vocoders initialised!");
  }
};

WASM_EXPORT(PitchShiftProcessor_init)
PitchShiftProcessor* PitchShiftProcessor_init(unsigned sample_rate) {
  // We only expect there to be one instance, so should be fine memory-wise??
  return new PitchShiftProcessor(sample_rate);
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
