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

// const float PITCH_SHIFT_FACTOR = std::pow(2, -6/12);
const float PITCH_SHIFT_FACTOR = 1.5;

class PitchShiftProcessor {
public:
  PitchShiftProcessor(): m_frame_count(0), m_fft_error(new char[512]) {
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
        m_output_channels_buffer.push_back({0});
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

      auto out_buffer_start = m_output_channels_buffer[input_channel].data();
      // Average in new samples with output block
      for (unsigned i = 0; i < BUFFER_SIZE; i++) {
        out_buffer_start[i] += transformed[i].real() * FRAME_SIZE / BUFFER_SIZE;
        // out_buffer_start[i] += transformed[i].real() * FRAME_SIZE;
      }

      std::memcpy(&output_channels[input_channel * FRAME_SIZE], m_output_channels_buffer[input_channel].data(), FRAME_SIZE * sizeof(*output_channels));

      // Shift committed samples out of buffer
      std::memmove(out_buffer_start, out_buffer_start + FRAME_SIZE, sizeof(float) * (BUFFER_SIZE - FRAME_SIZE));
      // Zero out last output frame
      std::memset(&out_buffer_start[BUFFER_SIZE - FRAME_SIZE], 0, FRAME_SIZE * sizeof(float));
    }

    m_frame_count++;
    return true;
  }

private:
  unsigned m_frame_count;
  std::unique_ptr<const char> m_fft_error;
  std::vector<std::array<float, BUFFER_SIZE>> m_input_channels_buffer;
  std::vector<std::array<float, BUFFER_SIZE>> m_output_channels_buffer;
  std::vector<std::array<double, BUFFER_SIZE>> m_input_phases;
  std::vector<std::array<double, BUFFER_SIZE>> m_output_phases;

  std::vector<std::complex<float>> pitch_shift(
    std::vector<std::complex<float>> &input,
    double* input_phases,
    double* output_phases
) {
    const double two_pi = 2.0 * M_PI;
    const double hop = FRAME_SIZE;        // S
    const double N = BUFFER_SIZE;

    std::vector<std::complex<float>> output(BUFFER_SIZE, {0.0f, 0.0f});

    for (unsigned i = 0; i < BUFFER_SIZE; i++) {
      double real = input[i].real();
      double imag = input[i].imag();

      double mag = std::sqrt(real * real + imag * imag);
      double phase = std::atan2(imag, real);

      // --- Phase difference ---
      double delta = phase - input_phases[i];
      input_phases[i] = phase;

      // Wrap to [-pi, pi]
      while (delta > M_PI) delta -= two_pi;
      while (delta < -M_PI) delta += two_pi;

      // Expected phase advance
      double expected = two_pi * hop * i / N;

      // Remove expected advance
      double deviation = delta - expected;

      // Wrap again (VERY important)
      while (deviation > M_PI) deviation -= two_pi;
      while (deviation < -M_PI) deviation += two_pi;

      // True frequency (in bins)
      double true_bin = i + deviation * N / (two_pi * hop);

      // --- Apply pitch shift ---
      double target = true_bin * PITCH_SHIFT_FACTOR;

      // Skip only if truly out of range
      if (target < 0.0 || target >= N - 1) {
        continue;
      }

      int bin0 = (int)std::floor(target);
      int bin1 = bin0 + 1;
      double frac = target - bin0;

      // --- Reconstruct phase ---
      double new_phase_increment = (expected + deviation) * PITCH_SHIFT_FACTOR;
      output_phases[bin0] += new_phase_increment;

      double out_phase = output_phases[bin0];

      // Convert back to complex
      float out_real = (float)(mag * std::cos(out_phase));
      float out_imag = (float)(mag * std::sin(out_phase));

      std::complex<float> c(out_real, out_imag);

      // --- Distribute energy ---
      output[bin0] += c * (float)(1.0 - frac);
      output[bin1] += c * (float)(frac);
    }

    return output;
}

  // This algorithm is based on https://csg.csail.mit.edu/6.375/6_375_2016_www/handouts/labs
  // I don't fully understand how it works
  // std::vector<std::complex<float>> pitch_shift(
  //   std::vector<std::complex<float>> &input,
  //   double* input_phases,
  //   double* output_phases
//   ) {
//     std::vector<std::complex<float>> output(BUFFER_SIZE, 0);
//     for (unsigned i = 0; i < BUFFER_SIZE; i++) {
//       utils::complexMP<double> mp(input[i]);
//       auto phase_diff = mp.phase() - input_phases[i];
//       input_phases[i] = mp.phase();

//       // Wrap to [-pi, pi]
//       while (phase_diff > M_PI) phase_diff -= 2.0 * M_PI;
//       while (phase_diff < -M_PI) phase_diff += 2.0 * M_PI;
//       // Acount for expected phase advance
//       double expected_phase_advance = 2.0 * M_PI * FRAME_SIZE * i / BUFFER_SIZE;
//       // Compute deviation from expected
//       double deviation = phase_diff - expected_phase_advance;

//       // Wrap to [-pi, pi]
//       while (deviation > M_PI) deviation -= 2.0 * M_PI;
//       while (deviation < -M_PI) deviation += 2.0 * M_PI;

//       phase_diff -= expected_phase_advance; // TODO put back?


//       double true_bin = i + deviation * BUFFER_SIZE / (2.0 * M_PI * FRAME_SIZE);
//       double target = true_bin * PITCH_SHIFT_FACTOR;
//       // unsigned target_bin = i * PITCH_SHIFT_FACTOR;
//       //
//       // unsigned next_bin = (i + 1) * PITCH_SHIFT_FACTOR; // TODO needed?
//       // if (next_bin == target_bin || target_bin > BUFFER_SIZE || target_bin < 0) {
//       if (target >= BUFFER_SIZE - 1 || target < 0) {
//         console::error("CONTINUING, phase_diff is " + s(phase_diff));
//         continue;
//       }
//       console::log("NOT CONTINUING");

//       // We're likely "in between" two bins, and need to interolate
//       int bin0 = (int)std::floor(target);
//       int bin1 = bin0 + 1;
//       double frac = target - bin0;

//       // double new_phase = output_phases[bin0] + deviation * PITCH_SHIFT_FACTOR;
//       double new_phase = output_phases[bin0] + (phase_diff - expected_phase_advance) * PITCH_SHIFT_FACTOR;

//       // auto shifted = phase_diff * PITCH_SHIFT_FACTOR;
//       output_phases[bin0] += new_phase;

//       auto c = utils::complexMP<float>(mp.magnitude(), new_phase).to_complex();
//       if (i > 10) {
//         console::log("The result: Real: " + s(c.real()) + "Imag: " + s(c.imag()));
//       }
//       output[bin0] += c * (float)(1.0 - frac);
//       output[bin1] += c * (float)(frac);
//       // output[target_bin] = utils::complexMP(mp.magnitude(), output_phases[target_bin]).to_complex();
//     }

//     return output;
//   }
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
