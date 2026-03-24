#include <cstddef>
#include <cstring>
#include <string>
#include <vector>

#include "wasm_helpers.h"
#include "utils.h"

#include "StftPitchShift/StftPitchShiftCore.h"
#include "StftPitchShift/STFT.h"

// This is defined by JavaScript's AudioWorklet API, so we should be able
// to assume that all input and output frames have this length
const size_t FRAME_SIZE = 128;
// How much we feed STFT every time
constexpr size_t WINDOW_SIZE = 2048;
const size_t FRAMES_PER_WINDOW = WINDOW_SIZE / FRAME_SIZE;

const size_t overlap = 32;

const std::tuple<size_t, size_t> stft_framesize = { WINDOW_SIZE, WINDOW_SIZE };
const size_t hopsize = std::get<1>(stft_framesize) / overlap;
const size_t total_buffer_size =
  std::get<0>(stft_framesize) +
  std::get<1>(stft_framesize);


const float PITCH_SHIFT_FACTOR = 1;

// enum class WindowStatus {
//   READY,
//   NOT_READY,
// };

struct ChannelStuff {
  std::vector<double> output_buffer;
  std::vector<double> input_buffer;
  // TODO Example uses shared_ptr, why?
  // std::unique_ptr<stftpitchshift::StftPitchShiftCore<double>> core;
  // std::unique_ptr<stftpitchshift::STFT<double>> stft;
  std::shared_ptr<stftpitchshift::StftPitchShiftCore<double>> core;
  std::shared_ptr<stftpitchshift::STFT<double>> stft;
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
    utils::span2d<float> output
  ) {
    ensure_channels_initialised(input.count());
    for (unsigned channel = 0; channel < input.count(); channel++) {
    // for (unsigned channel = 0; channel < 1; channel++) {
      auto &channel_stuff = m_channels_stuff[channel];
      // Shift input buffer
      std::copy(
        channel_stuff.input_buffer.begin() + FRAME_SIZE,
        // channel_stuff.input_buffer.begin() + WINDOW_SIZE,
        channel_stuff.input_buffer.end(),
        channel_stuff.input_buffer.begin()
      );

      // Copy in new samples
      // console::log("Just copying' input");
      std::transform(
        input[channel].begin(),
        input[channel].end(),
        channel_stuff.input_buffer.begin() + (total_buffer_size - FRAME_SIZE),
        [](float value) { return static_cast<double>(value); }
      );

      if (m_frame_count % (FRAMES_PER_WINDOW) == 1) {
      // if (m_frame_count % (FRAMES_PER_WINDOW * 2) == 1) {
        channel_stuff.core->factors({ PITCH_SHIFT_FACTOR });
        // channel_stuff.core->quefrency(0 * 1e-3);
        channel_stuff.core->quefrency(0);
        channel_stuff.core->distortion(1);
        channel_stuff.core->normalization(false);

        // console::log("Before pitch shift");
        (*channel_stuff.stft)(channel_stuff.input_buffer, channel_stuff.output_buffer, [&](std::span<std::complex<double>> dft) {
          channel_stuff.core->shiftpitch(dft);
        });
        // console::log("After pitch shift");
        // TODO do the pitch shift :)
        // For now, just copy the input to the output
        // std::copy(
        //   channel_stuff.input_buffer.begin(),
        // //  channel_stuff.input_buffer.begin() + WINDOW_SIZE,
        //   channel_stuff.input_buffer.end(),
        //   channel_stuff.output_buffer.begin()
        // );
      } else {
        // Shift the output
        // console::log("Just shiftin' output");
        std::copy(
          channel_stuff.output_buffer.begin() + FRAME_SIZE,
          // channel_stuff.output_buffer.begin() + WINDOW_SIZE,
          channel_stuff.output_buffer.end(),
          channel_stuff.output_buffer.begin()
        );
      }

      // console::log("Just copying' output");
      // Copy one frame of the output buffer to the output
      std::transform(
        channel_stuff.output_buffer.begin(),
        channel_stuff.output_buffer.begin() + FRAME_SIZE,
        output[channel].begin(),
        [](double value) { return static_cast<float>(value); }
      );
      std::transform(
        channel_stuff.output_buffer.begin(),
        channel_stuff.output_buffer.begin() + FRAME_SIZE,
        output[channel].begin(),
        [](double value) { return static_cast<float>(value); }
      );
      // Kanske inte asviktigt?
      // std::fill(
      //   channel_stuff.output_buffer.end() - FRAME_SIZE,
      //   channel_stuff.output_buffer.end(),
      //   0
      // );
      // console::log("Copied output!");
    }
    m_frame_count++;
    return true;
  }

private:
  unsigned m_frame_count = 0;
  unsigned m_sample_rate;
  std::vector<ChannelStuff> m_channels_stuff;

  void ensure_channels_initialised(size_t num_channels) {
    auto num_existing_channels = m_channels_stuff.size();
    if (num_existing_channels > 0) {
      if (num_existing_channels != num_channels) {
        console::error("Channels already initialised with " + s(num_existing_channels) + ", trying to reinitialise with " + s(num_channels));
        browser_assert(false && "Error initialising channels");
      }
      // Already initialised
      return;
    }

    for (size_t i = 0; i < num_channels; i++) {
      ChannelStuff channel = {
        // .output_buffer = std::vector<double>(WINDOW_SIZE),
        // .input_buffer = std::vector<double>(WINDOW_SIZE),
        .output_buffer = std::vector<double>(total_buffer_size),
        .input_buffer = std::vector<double>(total_buffer_size),
        .core = std::make_shared<stftpitchshift::StftPitchShiftCore<double>>(stft_framesize, hopsize, m_sample_rate),
        .stft = std::make_shared<stftpitchshift::STFT<double>>(stft_framesize, hopsize)
      };
      // m_channels_stuff.push_back(std::move(channel));
      m_channels_stuff.push_back((channel));
    }
    console::log(s(m_channels_stuff.size()) + " channels initialised");
    browser_assert(m_channels_stuff.size() == num_channels && "Channel number missmatch!");
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
  utils::span2d<float> input(input_channels, input_num_channels, FRAME_SIZE);
  utils::span2d<float> output(output_channels, output_num_channels, FRAME_SIZE);
  return self->process(input, output);
}
