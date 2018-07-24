#ifndef ZFP_MEMORY_H
#define ZFP_MEMORY_H

#include <algorithm>
#include <cstdlib>
#include "zfp/types.h"

namespace zfp {

inline void*
allocate(size_t size)
{
  return new uchar[size];
}

// allocate size bytes with alignment
inline void*
allocate_aligned(size_t size, size_t alignment)
{
#if defined(__USE_XOPEN2K) && defined(ZFP_WITH_ALIGNED_ALLOC)
  void* ptr;

  #ifdef __MINGW32__
  ptr = __mingw_aligned_malloc(size, alignment);
  #elif defined(_WIN32)
  ptr = _aligned_malloc(size, alignment);
  #else
  posix_memalign(&ptr, alignment, size);
  #endif

  return ptr;
#else
  return malloc(size);
#endif
}

// deallocate memory pointed to by ptr
template <typename T>
inline void
deallocate(T* ptr)
{
  delete[] ptr;
}

template <typename T>
inline void
deallocate_aligned(T* ptr)
{
#if defined(__USE_XOPEN2K) && defined(ZFP_WITH_ALIGNED_ALLOC)

  if (ptr)
  #ifdef __MINGW32__
    __mingw_aligned_free(ptr);
  #elif defined(_WIN32)
    _aligned_free(ptr);
  #else
    free(ptr);
  #endif

#else
  if (ptr)
    free(ptr);
#endif
}

// reallocate size bytes
template <typename T>
inline void
reallocate(T*& ptr, size_t size)
{
  zfp::deallocate(ptr);
  ptr = static_cast<T*>(zfp::allocate(size));
}

template <typename T>
inline void
reallocate_aligned(T*& ptr, size_t size, size_t alignment)
{
  zfp::deallocate_aligned(ptr);
  ptr = static_cast<T*>(zfp::allocate_aligned(size, alignment));
}

// clone array 'T src[count]'
template <typename T>
inline void
clone(T*& dst, const T* src, size_t count)
{
  zfp::deallocate(dst);
  if (src) {
    dst = static_cast<T*>(zfp::allocate(count * sizeof(T)));
    std::copy(src, src + count, dst);
  }
  else
    dst = 0;
}

template <typename T>
inline void
clone_aligned(T*& dst, const T* src, size_t count, size_t alignment)
{
  zfp::deallocate_aligned(dst);
  if (src) {
    dst = static_cast<T*>(zfp::allocate_aligned(count * sizeof(T), alignment));
    std::copy(src, src + count, dst);
  }
  else
    dst = 0;
}

}

#endif
