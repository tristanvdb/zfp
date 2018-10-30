#ifndef ZFP_ARRAY_EXCEPTION_H
#define ZFP_ARRAY_EXCEPTION_H

#include <stdexcept>
#include <string>

namespace zfp {

class header_exception : public std::exception {
public:
  header_exception(const char* msg) : msg(msg) {}

  header_exception(const std::string& msg) : msg(msg) {}

  virtual ~header_exception() throw (){}

  virtual const char* what() const throw () {
    return msg.c_str();
  }

protected:
  std::string msg;
};

}

#endif
