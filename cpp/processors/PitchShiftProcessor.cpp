#include <cstddef>
#include <cstring>
#include <string>
#include <vector>

#include "wasm_helpers.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output frames have this length
const size_t FRAME_SIZE = 128;
constexpr size_t WINDOW_SIZE = 512;
const size_t FRAMES_PER_WINDOW = WINDOW_SIZE / FRAME_SIZE;


enum class WindowStatus {
  READY,
  NOT_READY,
};

class PitchShiftProcessor {
public:
  PitchShiftProcessor(unsigned sample_rate):
    m_frame_count(0),
    m_sample_rate(sample_rate) {
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
    if (shift_in_input(input_channels, input_num_channels) == WindowStatus::NOT_READY) {
      console::log("Not ready, writing zeros...");
      std::memset(output_channels, 0, FRAME_SIZE * input_num_channels * sizeof(float));
      return true;
    }

    for (unsigned channel = 0; channel < input_num_channels; channel++) {
      auto input_start = m_input_windows[channel].data();
      std::memcpy(&output_channels[channel * FRAME_SIZE], input_start, FRAME_SIZE * sizeof(float));
    }
    return true;
  }

private:
  unsigned m_frame_count;
  unsigned m_sample_rate;
  std::vector<std::array<float, WINDOW_SIZE>> m_input_windows;

  WindowStatus shift_in_input(float *input_channels, size_t num_channels) {
    auto num_existing_windows = m_input_windows.size();
    if (num_existing_windows == 0) {
      for (size_t i = 0; i < num_channels; i++) {
        m_input_windows.push_back({0});
      }
      console::log("Input windows initialised with " + s(num_channels) + " channels");
    }
    if (num_existing_windows > 0 && num_existing_windows != num_channels) {
      console::error("Input windows already initialised with " + s(num_existing_windows) + " channels");
      browser_assert(false && "Window error");
    }

    for (size_t i = 0; i < m_input_windows.size(); i++) {
      auto win_start = m_input_windows[i].data();
      std::memmove(win_start, &win_start[FRAME_SIZE], (WINDOW_SIZE - FRAME_SIZE) * sizeof(float));
      std::memcpy(&win_start[WINDOW_SIZE - FRAME_SIZE], input_channels, FRAME_SIZE * sizeof(float));
    }

    m_frame_count++;

    if (m_frame_count == FRAMES_PER_WINDOW) {
      console::log("Window ready!");
    }
    if (m_frame_count >= FRAMES_PER_WINDOW) {
      return WindowStatus::READY;
    }
    return WindowStatus::NOT_READY;
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
