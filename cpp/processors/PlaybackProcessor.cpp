#include <cstddef>
#include <cstdint>
#include <cstring>
#include <span>
#include <string>

#include "wasm_helpers.h"

WASM_IMPORT void _console_log(const char *str);

// TODO maybe namespace instead
struct console {
  static void log(const std::string& str) {
    _console_log(str.c_str());
  }
};

template <typename T> struct span2d {
  T* data;
  size_t rows;
  size_t cols;

  std::span<T> operator[](size_t row) const {
    return std::span<T>(data + row * cols, cols);
  }

  size_t count() const {
    return rows;
  }
};

#define s(n) (std::to_string((n)))
#define p(n) (std::to_string(reinterpret_cast<uintptr_t>((n))))

class PlaybackProcessor {
public:
  PlaybackProcessor(unsigned sample_rate, float* inputs, int num_channels, int channel_length)
    : m_sample_rate(sample_rate)
    , m_src_channels(inputs, num_channels, channel_length) {

    console::log("PlaybackProcessor initialised!");
    console::log("Start pointer: " + p(inputs));
    console::log("Channelzzz: " + s(m_src_channels.count()));
    console::log("Sample rate: " + s(m_sample_rate));
    console::log("Input channel length: " + s(channel_length));
    console::log("Channel 0 length: " + s(m_src_channels.cols));
    console::log("Channel 1 length: " + s(m_src_channels.cols));
  }

  bool process(float *output_channels_ptr, unsigned num_channels, unsigned output_channel_length, float playback_speed) {
    if (m_src_index >= get_input_channel_length()) {
      std::memset(output_channels_ptr, 0, output_channel_length * num_channels * sizeof(*output_channels_ptr));
      return true;
    }

    span2d<float> output_channels(output_channels_ptr, num_channels, output_channel_length);
    size_t curr_src_index = m_src_index;

    // TODO min of output channels and input channels?
    for (unsigned channel_index = 0; channel_index < num_channels; channel_index++) {
      for (unsigned sample_index = 0; sample_index < output_channel_length; sample_index++) {
        curr_src_index = m_src_index + sample_index * playback_speed;
        output_channels[channel_index][sample_index] = m_src_channels[channel_index][curr_src_index];
      }
    }

    m_src_index = curr_src_index;
    return true;
  }

private:
  size_t m_src_index = 0;
  unsigned m_sample_rate = 0;
  span2d<float> m_src_channels;

  size_t get_input_channel_length() {
    return m_src_channels.cols;
  }
};

WASM_EXPORT(PlaybackProcessor_init)
PlaybackProcessor* PlaybackProcessor_init(unsigned sample_rate, float* inputs, int num_channels, int channel_length) {
  // We only expect there to be one instance, so should be fine memory-wise??
  return new PlaybackProcessor(sample_rate, inputs, num_channels, channel_length);
}

WASM_EXPORT(PlaybackProcessor_process)
bool PlaybackProcessor_process(PlaybackProcessor *self, float *output_channels, int num_channels, int channel_length, float playback_speed) {
  return self->process(output_channels, num_channels, channel_length, playback_speed);
}
