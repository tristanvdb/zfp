#ifndef ZFP_ARRAY_UTILS_H
#define ZFP_ARRAY_UTILS_H

#include "zfparray1.h"
#include "zfparray2.h"
#include "zfparray3.h"

#include <cstddef>

namespace zfp {

zfp::array* construct_from_stream(const zfp::header& header, const uchar* buffer, size_t bufferSize = 0)
{
  try {
    return new zfp::array1f(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  try {
    return new zfp::array1d(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  try {
    return new zfp::array2f(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  try {
    return new zfp::array2d(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  try {
    return new zfp::array3f(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  try {
    return new zfp::array3d(header, buffer, bufferSize);
  } catch (const std::invalid_argument& e) {}

  return 0;
}

}

#endif
