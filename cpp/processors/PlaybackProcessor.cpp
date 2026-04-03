#include <cstddef>
#include <cstring>
#include <string>

#include "wasm_helpers.h"
#include "utils.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output channels have this length
const unsigned FRAME_SIZE = 128;

constexpr float NUM_PROGRESS_REPORTS_PER_SECOND = 100;
constexpr float PROGRESS_REPORT_FREQUENCY = 1.0 / NUM_PROGRESS_REPORTS_PER_SECOND;

WASM_IMPORT void report_current_progress_in_samples(size_t samples);

class PlaybackProcessor {
public:
  PlaybackProcessor(unsigned sample_rate, float* inputs, int num_channels, int channel_length)
    : m_sample_rate(sample_rate)
    , m_src_channels(inputs, num_channels, channel_length) {

    console::log("PlaybackProcessor initialised!");
    console::log("Channels: " + s(m_src_channels.count()));
    console::log("Sample rate: " + s(m_sample_rate));
  }

  bool process(utils::span2d<float> output, float playback_speed, bool is_playing, std::tuple<size_t, size_t> limits) {
    int progress_report_frequency_samples = m_sample_rate * PROGRESS_REPORT_FREQUENCY;

    if (is_playing && (m_src_index % progress_report_frequency_samples) < FRAME_SIZE) {
      report_current_progress_in_samples(m_src_index);
    }

    if (!is_playing) {
      std::fill(output[0].begin(), output[output.count() - 1].end(), 0);
      return true;
    }

    // Loop when we hit limits
    if (
      m_src_index >= get_input_channel_length() ||
      m_src_index < std::get<0>(limits) ||
      m_src_index >= std::get<1>(limits)
    ) {
      m_src_index = std::get<0>(limits);
      report_current_progress_in_samples(m_src_index);
    }

    size_t curr_src_index = m_src_index;

    // TODO min of output channels and input channels?
    for (unsigned channel = 0; channel < output.count(); channel++) {
      for (unsigned sample_index = 0; sample_index < FRAME_SIZE; sample_index++) {
        curr_src_index = m_src_index + sample_index * playback_speed;
        output[channel][sample_index] = m_src_channels[channel][curr_src_index];
      }
    }

    m_src_index = curr_src_index;
    return true;
  }

private:
  size_t m_src_index = 0;
  unsigned m_sample_rate = 0;
  utils::span2d<float> m_src_channels;

  size_t get_input_channel_length() {
    return m_src_channels.cols();
  }
};

WASM_EXPORT(PlaybackProcessor_init)
PlaybackProcessor* PlaybackProcessor_init(unsigned sample_rate, float* inputs, int num_channels, int channel_length) {
  // We only expect there to be one instance, so should be fine memory-wise??
  return new PlaybackProcessor(sample_rate, inputs, num_channels, channel_length);
}

WASM_EXPORT(PlaybackProcessor_process)
bool PlaybackProcessor_process(
  PlaybackProcessor *self,
  float *input_channels,
  int input_num_channels,
  float *output_channels,
  int output_num_channels,
  float playback_speed,
  bool is_playing,
  int lower_playback_limit,
  int upper_playback_limit
) {
  (void)input_channels;
  (void)input_num_channels;

  utils::span2d<float> output(output_channels, output_num_channels, FRAME_SIZE);
  std::tuple<size_t, size_t> playback_limits(lower_playback_limit, upper_playback_limit);
  return self->process(output, playback_speed, is_playing, playback_limits);
}
