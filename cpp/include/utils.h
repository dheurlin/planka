#pragma once

#include <complex>
#include <cstddef>
#include <span>

namespace utils {

template <typename T> class span2d {
private:
  T* m_data;
  size_t m_rows;
  size_t m_cols;

public:
  span2d(T* data, size_t rows, size_t cols): m_data(data), m_rows(rows), m_cols(cols) {}

  std::span<T> operator[](size_t row) const {
    return std::span<T>(m_data + row * m_cols, m_cols);
  }

  size_t count() const {
    return m_rows;
  }

  size_t cols() const {
    return m_cols;
  }
};

template <typename T> class complexMP {
private:
  T m_magnitude;
  T m_phase;

public:
  complexMP<T>(std::complex<T> complex): m_magnitude(abs(complex)), m_phase(arg(complex)) {}

  T magnitude() const {
    return m_magnitude;
  }

  T phase() const {
    return m_phase;
  }

  void set_phase(T new_phase) {
    m_phase = new_phase;
  }

  std::complex<T> to_complex() const {
    auto i = std::complex<T>(0.0, 1.0);
    return m_magnitude * std::exp(i * m_phase);
  }
};

}
