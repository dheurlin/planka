#include <complex>
#include <cstddef>
#include <span>

#include "vendor/simple_fft/fft.h"

#include "wasm_helpers.h"

class SimpleFFTAdapter {
public:
  SimpleFFTAdapter(size_t size): m_size(size), m_error(new char[512]) {};

  void rfft(float *in, float *out) {
    auto error = m_error.get();

    auto out_complex = reinterpret_cast<std::complex<float>*>(out);
    auto ok = simple_fft::FFT(in, out_complex, m_size, error);
    if (!ok) {
      console::error("FFT Failed: " + std::string(error));
      browser_assert(false && "FFT Failed!");
    }
  }

  void rifft(float *in, float *out) {
    auto error = m_error.get();
    auto in_complex = reinterpret_cast<std::complex<float>*>(in);

    // Hypothesis: We're only getting size / 2 complex samples back,
    // as negative frequencies are discarded. We need to reconstruct those.

    // Create full complex spectrum
    std::vector<std::complex<float>> in_complex_full(m_size);

    // Copy positive frequencies
    for (size_t i = 0; i <= m_size/2; i++) {
        in_complex_full[i] = in_complex[i];
    }

    // Reconstruct negative frequencies (Hermitian symmetry)
    for (size_t i = 1; i < m_size/2; i++) {
        in_complex_full[m_size - i] = std::conj(in_complex[i]);
    }

    auto ok = simple_fft::IFFT(in_complex_full, m_size, error);
    if (!ok) {
      console::error("IFFT Failed: " + std::string(error));
      browser_assert(false && "IFFT Failed!");
    }

    for (size_t i = 0; i < m_size; i++) {
      out[i] = in_complex_full[i].real();
    }

    // auto in_complex_arr = std::span(in_complex, m_size / 2 + 1);


    // auto out_arr = std::span(out, m_size);
    // std::transform(std::begin(in_complex_arr), std::cend(in_complex_arr), std::cbegin(out_arr), [](std::complex<float> &c) {
    //   return c.real();
    // });
  }

private:
  size_t m_size;
  std::unique_ptr<const char> m_error;
};

