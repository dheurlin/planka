#pragma once

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

}
