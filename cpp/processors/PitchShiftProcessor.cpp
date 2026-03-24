#include <optional>
#include <vector>

#include "wasm_helpers.h"
#include "utils.h"

#include "StftPitchShift/StftPitchShiftCore.h"
#include "StftPitchShift/STFT.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output frames have this length
const size_t FRAME_SIZE = 128;
// How much we feed STFT every time
constexpr size_t WINDOW_SIZE = 4096;
const size_t FRAMES_PER_WINDOW = WINDOW_SIZE / FRAME_SIZE;

const size_t overlap = 32;

// We're tricking STFT that we're working with WINDOW_SIZE samples at a time,
// by collecting the FRAME_SIZE frames into a buffer and only calling it
// when that gets full. That's why stft_framesize is different from FRAME_SIZE
const std::tuple<size_t, size_t> stft_framesize = { WINDOW_SIZE, WINDOW_SIZE };
const size_t hopsize = std::get<1>(stft_framesize) / overlap;
const size_t total_buffer_size =
  std::get<0>(stft_framesize) +
  std::get<1>(stft_framesize);


struct ChannelStuff {
  std::vector<double> output_buffer;
  std::vector<double> input_buffer;
  std::unique_ptr<stftpitchshift::StftPitchShiftCore<double>> core;
  std::unique_ptr<stftpitchshift::STFT<double>> stft;
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
    utils::span2d<float> input,
    utils::span2d<float> output,
    float target_pitch_shift_factor,
    float playback_speed
  ) {
    auto &channels_stuff = get_or_initialise_channels(input.count());

    // Compensate for the effects of playback speed
    auto effective_pitch_shift_factor = target_pitch_shift_factor / playback_speed;

    for (unsigned channel = 0; channel < input.count(); channel++) {
      auto &channel_stuff = channels_stuff[channel];
      // Shift input buffer
      std::copy(
        channel_stuff.input_buffer.begin() + FRAME_SIZE,
        channel_stuff.input_buffer.end(),
        channel_stuff.input_buffer.begin()
      );

      // Copy in new samples
      std::transform(
        input[channel].begin(),
        input[channel].end(),
        channel_stuff.input_buffer.end() - FRAME_SIZE,
        [](float value) { return static_cast<double>(value); }
      );

      if (m_frame_count % FRAMES_PER_WINDOW == 1) {
        channel_stuff.core->factors({ effective_pitch_shift_factor });

        (*channel_stuff.stft)(channel_stuff.input_buffer, channel_stuff.output_buffer, [&](std::span<std::complex<double>> dft) {
          channel_stuff.core->shiftpitch(dft);
        });
      }

      // Copy one frame of the output buffer to the output
      std::transform(
        channel_stuff.output_buffer.begin(),
        channel_stuff.output_buffer.begin() + FRAME_SIZE,
        output[channel].begin(),
        [](double value) { return static_cast<float>(value); }
      );

      // Shift the output one frame
      std::copy(
        channel_stuff.output_buffer.begin() + FRAME_SIZE,
        channel_stuff.output_buffer.end(),
        channel_stuff.output_buffer.begin()
      );

      // TODO clear output?
    }
    m_frame_count++;
    return true;
  }

private:
  unsigned m_frame_count = 0;
  unsigned m_sample_rate;
  std::optional<std::vector<ChannelStuff>> m_channels_stuff = std::nullopt;

  std::vector<ChannelStuff> &get_or_initialise_channels(size_t num_channels) {
    if (m_channels_stuff.has_value()) {
      auto num_existing_channels = m_channels_stuff->size();
      if (num_existing_channels != num_channels) {
        console::error("Channels already initialised with " + s(num_existing_channels) + ", trying to reinitialise with " + s(num_channels));
        browser_assert(false && "Error initialising channels");
      }
      // Already initialised
      return *m_channels_stuff;
    }

    m_channels_stuff = std::vector<ChannelStuff>();

    for (size_t i = 0; i < num_channels; i++) {
      ChannelStuff channel = {
        .output_buffer = std::vector<double>(total_buffer_size),
        .input_buffer = std::vector<double>(total_buffer_size),
        .core = std::make_unique<stftpitchshift::StftPitchShiftCore<double>>(stft_framesize, hopsize, m_sample_rate),
        .stft = std::make_unique<stftpitchshift::STFT<double>>(stft_framesize, hopsize)
      };
     m_channels_stuff->push_back(std::move(channel));
    }

    console::log(s(m_channels_stuff->size()) + " channels initialised");
    browser_assert(m_channels_stuff->size() == num_channels && "Channel number missmatch!");

    return *m_channels_stuff;
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
  unsigned output_num_channels,
  float target_pitch_shift_factor,
  float playback_speed
) {
  utils::span2d<float> input(input_channels, input_num_channels, FRAME_SIZE);
  utils::span2d<float> output(output_channels, output_num_channels, FRAME_SIZE);
  return self->process(input, output, target_pitch_shift_factor, playback_speed);
}
