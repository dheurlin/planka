#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>
#include <string>

#include "wasm_helpers.h"

WASM_IMPORT void _console_log(const char *str);

void console_log(std::string str) {
  _console_log(str.c_str());
}

#define s(n) (std::to_string((n)))
#define p(n) (std::to_string(reinterpret_cast<uintptr_t>((n))))

class PlaybackProcessor {
public:
  PlaybackProcessor(float* inputs, int num_channels, int channel_length) {
    for (int channel_ix = 0; channel_ix < num_channels; channel_ix++) {
      float *start = &inputs[channel_ix * channel_length];
      m_input_channels.emplace_back(start, start + channel_length);
    }

    console_log("PlaybackProcessor initialised!");
    console_log("Start pointer: " + p(inputs));
    console_log("Channelzzz: " + s(m_input_channels.size()));
    console_log("Input channel length: " + s(channel_length));
    console_log("Channel 0 length: " + s(m_input_channels[0].size()));
    console_log("Channel 1 length: " + s(m_input_channels[1].size()));
  }

  bool process(float *output_channels, unsigned num_channels, unsigned output_channel_length) {
    if (m_buffer_index >= get_input_channel_length()) {
      std::memset(output_channels, 0, output_channel_length * num_channels * sizeof(*output_channels));
      return true;
    }

    // TODO min of output channels and input channels?
    for (unsigned channel_index = 0; channel_index < num_channels; channel_index++) {
      for (unsigned sample_index = 0; sample_index < output_channel_length; sample_index++) {
        output_channels[output_channel_length * channel_index + sample_index] = m_input_channels[channel_index][m_buffer_index + sample_index];
      }
    }

    m_buffer_index += output_channel_length;
    return true;
  }

private:
  std::vector<std::vector<float>> m_input_channels;
  size_t m_buffer_index = 0;

  size_t get_input_channel_length() {
    return m_input_channels[0].size();
  }
};

WASM_EXPORT(PlaybackProcessor_init)
PlaybackProcessor* PlaybackProcessor_init(float* inputs, int num_channels, int channel_length) {
  // We only expect there to be one instance, so should be fine memory-wise??
  return new PlaybackProcessor(inputs, num_channels, channel_length);
}

WASM_EXPORT(PlaybackProcessor_process)
bool PlaybackProcessor_process(PlaybackProcessor *self, float *output_channels, int num_channels, int channel_length) {
  return self->process(output_channels, num_channels, channel_length);
}
