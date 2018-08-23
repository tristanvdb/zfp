.. index::
   single: Header
.. _header:

Header
------

.. cpp:namespace:: zfp

..
  .. cpp:type:: header

.. cpp:type:: header

  This struct stores information needed to describe a compressed-array, should
  a user want to serialize it. Compressed-arrays always have 96 bit headers,
  stored in the buffer array. This header is fully compatible with the C API.
  ::

    typedef struct {
      uint32 buffer[3];
    } header;
