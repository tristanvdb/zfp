.. index::
   single: Exceptions
.. _exceptions:

Exceptions
----------

.. cpp:namespace:: zfp

..
  .. cpp:class:: header_exception : public std::exception

.. cpp:class:: header_exception : public std::exception

  Compressed arrays can throw this exception when calling the constructor taking
  a zfp_header and buffer. This exception will be thrown if the header is
  invalid or describes compressed data that is incompatible with this
  compressed-array. Also note this exception lies in the :cpp:any:`zfp`
  namespace.
