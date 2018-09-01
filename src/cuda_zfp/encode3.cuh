#ifndef CUZFP_ENCODE3_CUH
#define CUZFP_ENCODE3_CUH

#include "ull128.h"
#include "WriteBitter.cuh"
#include "shared.h"

#include "cuZFP.h"
#include "debug_utils.cuh"
#include "type_info.cuh"

#define ZFP_3D_BLOCK_SIZE 64
namespace cuZFP{

template<typename Scalar> 
__device__ __host__ inline 
void gather3(Scalar* q, const Scalar* p, int sx, int sy, int sz)
{
  uint x, y, z;
  for (z = 0; z < 4; z++, p += sz - 4 * sy)
    for (y = 0; y < 4; y++, p += sy - 4 * sx)
      for (x = 0; x < 4; x++, p += sx)
        *q++ = *p;
}

template<typename Scalar, typename Int, int BlockSize>
void __device__ fwd_cast(Int *iblock, const Scalar *fblock, int emax)
{
	Scalar s = quantize_factor(emax, Scalar());
  for(int i = 0; i < BlockSize; ++i)
  {
    iblock[i] = (Int) (s * fblock[i]);
  }
}

// forward decorrelating transform
template<class Int>
__device__ __host__
static void
fwd_xform_zy(Int* p)
{
	fwd_lift<Int,1>(p + 4 * threadIdx.x + 16 * threadIdx.z);
}
// forward decorrelating transform
template<class Int>
__device__ __host__
static void
fwd_xform_xz(Int* p)
{
	fwd_lift<Int, 4>(p + 16 * threadIdx.z + 1 * threadIdx.x);
}
// forward decorrelating transform
template<class Int>
__device__ __host__
static void
fwd_xform_yx(Int* p)
{
	fwd_lift<Int, 16>(p + 1 * threadIdx.x + 4 * threadIdx.z);
}

// forward decorrelating transform
template<class Int>
__device__ 
static void
fwd_xform(Int* p)
{
  fwd_xform_zy(p);
	__syncthreads();
	fwd_xform_xz(p);
	__syncthreads();
	fwd_xform_yx(p);
}

template<int BlockSize>
struct transform;

template<>
struct transform<64>
{
  template<typename Int>
  __device__ void fwd_xform(Int *p)
  {

    uint x, y, z;
    /* transform along x */
    for (z = 0; z < 4; z++)
      for (y = 0; y < 4; y++)
        fwd_lift<Int,1>(p + 4 * y + 16 * z);
    /* transform along y */
    for (x = 0; x < 4; x++)
      for (z = 0; z < 4; z++)
        fwd_lift<Int,4>(p + 16 * z + 1 * x);
    /* transform along z */
    for (y = 0; y < 4; y++)
      for (x = 0; x < 4; x++)
        fwd_lift<Int,16>(p + 1 * x + 4 * y);

   }

};

template<int BlockSize>
__device__
unsigned char* get_perm();

template<>
__device__
unsigned char* get_perm<64>()
{
  return c_perm;
}

template<>
__device__
unsigned char* get_perm<16>()
{
  return c_perm_2;
}

template<>
__device__
unsigned char* get_perm<4>()
{
  return c_perm_1;
}


template<typename Int, typename UInt, int BlockSize>
__device__ void fwd_order(UInt *ublock, const Int *iblock)
{
  unsigned char *perm = get_perm<BlockSize>();
  for(int i = 0; i < BlockSize; ++i)
  {
    ublock[i] = int2uint(iblock[perm[i]]);
  }
}

template<typename Int, int DIMS>
__device__ void fwd_xform(Int* p);

template<typename Int, int BlockSize> 
void inline __device__ encode_block(BlockWriter2<BlockSize> &stream,
                                    int maxbits,
                                    int maxprec,
                                    Int *iblock)
{
  transform<BlockSize> tform;
  tform.fwd_xform(iblock);

  typedef typename zfp_traits<Int>::UInt UInt;
  UInt ublock[BlockSize]; 
  fwd_order<Int, UInt, BlockSize>(ublock, iblock);

  uint intprec = CHAR_BIT * (uint)sizeof(UInt);
  uint kmin = intprec > maxprec ? intprec - maxprec : 0;
  uint bits = maxbits;
  uint i, k, m, n;
  uint64 x;
  //for(int p = 0; p < BlockSize; ++p) printf(" %llu \n", ublock[p]);

  for (k = intprec, n = 0; bits && k-- > kmin;) {
    /* step 1: extract bit plane #k to x */
    x = 0;
    for (i = 0; i < BlockSize; i++)
    {
      x += (uint64)((ublock[i] >> k) & 1u) << i;
    }
    //printf("plane %llu\n", x);
    //print_bits(x);
    /* step 2: encode first n bits of bit plane */
    m = min(n, bits);
    uint temp  = bits;
    bits -= m;
    x = stream.write_bits(x, m);
    
    //printf("rem plane %llu\n", x);
    /* step 3: unary run-length encode remainder of bit plane */
    for (; n < BlockSize && bits && (bits--, stream.write_bit(!!x)); x >>= 1, n++)
    {
      for (; n < BlockSize - 1 && bits && (bits--, !stream.write_bit(x & 1u)); x >>= 1, n++)
      {  
      }
    }
    //stream.print();
    //temp = temp - bits;
    //printf(" rem buts %d intprec %d k %d encoded_bits %d\n", (int)bits, (int)intprec, (int)k,(int)temp); 
  }
  
}
                                   
template<typename Scalar, int BlockSize>
void inline __device__ zfp_encode_block(Scalar *fblock,
                                        const int maxbits,
                                        const uint block_idx,
                                        Word *stream)
{
  BlockWriter2<BlockSize> block_writer(stream, maxbits, block_idx);
  int emax = max_exponent<Scalar, BlockSize>(fblock);
  int maxprec = precision(emax, get_precision<Scalar>(), get_min_exp<Scalar>());
  uint e = maxprec ? emax + get_ebias<Scalar>() : 0;
  if(e)
  {
    const uint ebits = get_ebits<Scalar>()+1;
    block_writer.write_bits(2 * e + 1, ebits);
    typedef typename zfp_traits<Scalar>::Int Int;
    Int iblock[BlockSize];
    fwd_cast<Scalar, Int, BlockSize>(iblock, fblock, emax);


    encode_block<Int, BlockSize>(block_writer, maxbits - ebits, maxprec, iblock);
  }
}

template<>
void inline __device__ zfp_encode_block<int, 64>(int *fblock,
                                             const int maxbits,
                                             const uint block_idx,
                                             Word *stream)
{
  BlockWriter2<64> block_writer(stream, maxbits, block_idx);
  const int intprec = get_precision<int>();
  encode_block<int, 64>(block_writer, maxbits, intprec, fblock);
}

template<>
void inline __device__ zfp_encode_block<long long int, 64>(long long int *fblock,
                                                       const int maxbits,
                                                       const uint block_idx,
                                                       Word *stream)
{
  BlockWriter2<64> block_writer(stream, maxbits, block_idx);
  const int intprec = get_precision<long long int>();
  encode_block<long long int, 64>(block_writer, maxbits, intprec, fblock);
}


template<typename Scalar, typename Int>
void 
inline __device__ floating_point_ops(const int &tid,
                                     Int *sh_q,
                                     uint *s_emax_bits,
                                     const Scalar *sh_data,
                                     Scalar *sh_reduce,
                                     int *sh_emax,
                                     const Scalar &thread_val,
                                     Word *blocks,
                                     uint &blk_idx)
{

  /** FLOATING POINT ONLY ***/
  get_max_exponent(tid, sh_data, sh_reduce, sh_emax);
	__syncthreads();
  /*** FLOATING POINT ONLY ***/
	Scalar w = quantize_factor(sh_emax[0], Scalar());
  /*** FLOATING POINT ONLY ***/
  // block tranform
  sh_q[tid] = (Int)(thread_val * w); // sh_q  = signed integer representation of the floating point value
  /*** FLOATING POINT ONLY ***/
	if (tid == 0)
  {
		s_emax_bits[0] = 1;

		int maxprec = precision(sh_emax[0], get_precision<Scalar>(), get_min_exp<Scalar>());

		uint e = maxprec ? sh_emax[0] + get_ebias<Scalar>() : 0;
		if(e)
    {
			blocks[blk_idx] = 2 * e + 1; // the bit count?? for this block
			s_emax_bits[0] = get_ebits<Scalar>() + 1;// this c_ebit = ebias
		}
	}
}


template<>
void 
inline __device__ floating_point_ops<int,int>(const int &tid,
                                     int *sh_q,
                                     uint *s_emax_bits,
                                     const int *sh_data,
                                     int *sh_reduce,
                                     int *sh_emax,
                                     const int &thread_val,
                                     Word *blocks,
                                     uint &blk_idx)
{
  s_emax_bits[0] = 0;
  sh_q[tid] = thread_val;
}


template<>
void 
inline __device__ floating_point_ops<long long int, long long int>(const int &tid,
                                     long long int *sh_q,
                                     uint *s_emax_bits,
                                     const long long int*sh_data,
                                     long long int *sh_reduce,
                                     int *sh_emax,
                                     const long long int &thread_val,
                                     Word *blocks,
                                     uint &blk_idx)
{
  s_emax_bits[0] = 0;
  sh_q[tid] = thread_val;
}

template<typename Scalar>
void
inline __device__
get_max_exponent(const int &tid, 
                 const Scalar *sh_data,
                 Scalar *sh_reduce, 
                 int *max_exponent)
{
	if (tid < 32)
  {
		sh_reduce[tid] = max(fabs(sh_data[tid]), fabs(sh_data[tid + 32]));
  }
	if (tid < 16)
  {
		sh_reduce[tid] = max(sh_reduce[tid], sh_reduce[tid + 16]);
  }
	if (tid < 8)
  {
		sh_reduce[tid] = max(sh_reduce[tid], sh_reduce[tid + 8]);
  }
	if (tid < 4)
  {
		sh_reduce[tid] = max(sh_reduce[tid], sh_reduce[tid + 4]);
  }
	if (tid < 2)
  {
		sh_reduce[tid] = max(sh_reduce[tid], sh_reduce[tid + 2]);
  }
	if (tid == 0)
  {
		sh_reduce[0] = max(sh_reduce[tid], sh_reduce[tid + 1]);
		max_exponent[0] = exponent(sh_reduce[0]);
	}
}


template<typename Scalar>
__device__
void 
encode (Scalar *sh_data,
	      const uint bits_per_block, 
        unsigned char *smem,
        uint blk_idx,
        Word *blocks)
{
  typedef typename zfp_traits<Scalar>::UInt UInt;
  typedef typename zfp_traits<Scalar>::Int Int;
  const int intprec = get_precision<Scalar>();

  const uint vals_per_block = 64;
  //shared mem that depends on scalar size
	__shared__ Scalar *sh_reduce;
	__shared__ Int *sh_q;
	__shared__ UInt *sh_p;

  // shared mem that always has the same size
	__shared__ int *sh_emax;
	__shared__ uint *sh_m, *sh_n;
	__shared__ unsigned char *sh_sbits;
	__shared__ Bitter *sh_bitters;
	__shared__ uint *s_emax_bits;

  //
  // These memory locations do not overlap (in time)
  // so we will re-use the same buffer to
  // conserve precious shared mem space
  //
	sh_reduce = &sh_data[0];
	sh_q = (Int*)&sh_data[0];
	sh_p = (UInt*)&sh_data[0];

	sh_sbits = &smem[0];
	sh_bitters = (Bitter*)&sh_sbits[vals_per_block];
	sh_m = (uint*)&sh_bitters[vals_per_block];
	sh_n = (uint*)&sh_m[vals_per_block];
	s_emax_bits = (uint*)&sh_n[vals_per_block];
	sh_emax = (int*)&s_emax_bits[1];

	uint tid = threadIdx.x + threadIdx.y * blockDim.x + threadIdx.z *blockDim.x*blockDim.y;

	Bitter bitter = make_bitter(0, 0);
	unsigned char sbit = 0;
	uint bsize = bits_per_block / vals_per_block; // TODO: bsize is this really rate?
	if (tid < bsize)
		blocks[blk_idx + tid] = 0; 

  Scalar thread_val = sh_data[tid];

	__syncthreads();
  
  //
  // this is basically a no-op for int types
  //
  floating_point_ops(tid,
                     sh_q,
                     s_emax_bits,
                     sh_data,
                     sh_reduce,
                     sh_emax,
                     thread_val,
                     blocks,
                     blk_idx);
 
	__syncthreads();

  // Decorrelation
	fwd_xform(sh_q);

	__syncthreads();

  // get negabinary representation
  // fwd_order in cpu code
	UInt u = int2uint(sh_q[c_perm[tid]]);
  // avoid race conditions: sh_q and sh_p point to the same loc
	__syncthreads();
	sh_p[tid] = u;
	__syncthreads();
  /**********************Begin encode block *************************/
	/* extract bit plane k to x[k] */
	long long unsigned y = 0;
	const long long unsigned mask = 1;
#pragma unroll 64
	for (uint i = 0; i < vals_per_block; i++)
  {
    // TODO: this is the main bottlenect in terms 
    // of # of instructions. We could could change
    // this to a lookup table or some sort of
    // binary matrix transpose.
		y += ((sh_p[i] >> tid) & mask) << i;
  }
  
	long long unsigned x = y;
  // From this point on for 32 bit types,
  // only tids < 32 have valid data
  
  
	__syncthreads();
	sh_m[tid] = 0;   
	sh_n[tid] = 0;

	// temporarily use sh_n as a buffer
  // these are setting up indices to things that have value
  // find the first 1 (in terms of most significant 
  // __clzll -- intrinsic for count the # of leading zeros 	
  sh_n[tid] = 64 - __clzll(x);
	__syncthreads();

	if (tid < intprec - 1)
  {
		sh_m[tid] = sh_n[tid + 1];
	}

	__syncthreads();
  // this is basically a scan
	if (tid == 0)
  {
    #pragma unroll
		for (int i = intprec - 2; i >= 0; --i)
    {
			if (sh_m[i] < sh_m[i + 1])
      {
				sh_m[i] = sh_m[i + 1];
      }
		}
	}

	__syncthreads();
	int bits = 128; // same for both 32 and 64 bit values 
	int n = 0;
	/* step 2: encode first n bits of bit plane */
	bits -= sh_m[tid];
	x >>= sh_m[tid];
	x = (sh_m[tid] != 64) * x;
	n = sh_m[tid];
	/* step 3: unary run-length encode remainder of bit plane */
	for (; n < vals_per_block && bits && (bits--, !!x); x >>= 1, n++)
  {
		for (; n < vals_per_block - 1 && bits && (bits--, !(x & 1u)); x >>= 1, n++);
  }
	__syncthreads();

	bits = (128 - bits);
	sh_n[tid] = min(sh_m[tid], bits);

	/* step 2: encode first n bits of bit plane */
	y = write_bitters(bitter, make_bitter(y, 0), sh_m[tid], sbit);
	n = sh_n[tid];
	/* step 3: unary run-length encode remainder of bit plane */
	for (; n < vals_per_block && bits && (bits-- && write_bitter(bitter, !!y, sbit)); y >>= 1, n++)
  {
		for (; n < vals_per_block - 1 && bits && (bits-- && !write_bitter(bitter, y & 1u, sbit)); y >>= 1, n++);
  }

	__syncthreads();
  

  // First use of both bitters and sbits
  if(tid < intprec)
  {
    sh_bitters[intprec - 1 - tid] = bitter;
    sh_sbits[intprec - 1 - tid] = sbit;
  }
	__syncthreads();

  // Bitter is a ulonglong2. It is just a way to have a single type
  // that contains 128bits
  // the max size of a single encoded bit plane is 127 bits in the degenerate case.
  // This is where every group test fails.

  // write out x writes to the first 64 bits and write out y writes to the second

	if (tid == 0)
  {
		uint tot_sbits = s_emax_bits[0];// sbits[0];
		uint rem_sbits = s_emax_bits[0];// sbits[0];
		uint offset = 0;
    const uint maxbits = bits_per_block; 
    uint tot = maxbits;
		for (int i = 0; i < intprec && tot_sbits < maxbits; i++)
    {
      uint temp = tot_sbits;
			if (sh_sbits[i] <= 64)
      {
				write_outx(sh_bitters, blocks + blk_idx, rem_sbits, tot_sbits, offset, i, sh_sbits[i], maxbits);
			}
			else
      {
        // I think  the 64 here is just capping out the bits it writes?
				write_outx(sh_bitters, blocks + blk_idx, rem_sbits, tot_sbits, offset, i, 64, maxbits);
        if (tot_sbits < maxbits)
        {
          write_outy(sh_bitters, blocks + blk_idx, rem_sbits, tot_sbits, offset, i, sh_sbits[i] - 64, maxbits);
        }
			}
      temp = tot_sbits - temp;
      tot -= sh_sbits[i];
		}
	} // end serial write

}

template<class Scalar>
__global__
void 
cudaEncode(const uint maxbits,
           const Scalar* scalars,
           Word *stream,
           const uint3 dims,
           const uint3 padded_dims,
           const uint tot_blocks)
{

  typedef unsigned long long int ull;
  const ull blockId = blockIdx.x +
                      blockIdx.y * gridDim.x +
                      gridDim.x * gridDim.y * blockIdx.z;

  // each thread gets a block so the block index is 
  // the global thread index
  const uint block_idx = blockId * blockDim.x + threadIdx.x;

  if(block_idx >= tot_blocks)
  {
    // we can't launch the exact number of blocks
    // so just exit if this isn't real
    return;
  }

  uint3 block_dims;
  block_dims.x = padded_dims.x >> 2; 
  block_dims.y = padded_dims.y >> 2; 
  block_dims.z = padded_dims.z >> 2; 

  // logical pos in 3d array
  uint3 block;
  block.x = (block_idx % block_dims.x) * 4; 
  block.y = ((block_idx/ block_dims.x) % block_dims.y) * 4; 
  block.z = (block_idx/ (block_dims.x * block_dims.y)) * 4; 
  // default strides
  int sx = 1;
  int sy = dims.x;
  int sz = dims.x * dims.y;
  //if(block_idx != 1) return;
  //uint offset = (logicalStart[2]*PaddedDims[1] + logicalStart[1])*PaddedDims[0] + logicalStart[0]; 
  uint offset = block.x * sx + block.y * sy + block.z * sz; 
  //printf("blk_idx %d block coords %d %d %d\n", block_idx, block.x, block.y, block.z);
  //printf("OFFSET %d\n", (int)offset); 
  Scalar fblock[ZFP_3D_BLOCK_SIZE]; 
  // TODO: gather partail
  gather3(fblock, scalars + offset, sx, sy, sz);
  //if(block_idx == 0)
  //for(int z = 0; z < 4; ++z)
  //{
  //  for(int y = 0; y < 4; ++y)
  //  {
  //    for(int x = 0; x < 4; ++x)
  //    {
  //      printf("%f ", fblock[z * 8 + y * 4 + x]);
  //    }
  //    printf("\n");
  //  }
  //}
  zfp_encode_block<Scalar, ZFP_3D_BLOCK_SIZE>(fblock, maxbits, block_idx, stream);  

}

size_t calc_device_mem3d(const uint3 encoded_dims, 
                         const int bits_per_block)
{
  const size_t vals_per_block = 64;
  const size_t size = encoded_dims.x * encoded_dims.y * encoded_dims.z; 
  size_t total_blocks = size / vals_per_block; 
  const size_t bits_per_word = sizeof(Word) * 8;
  const size_t total_bits = bits_per_block * total_blocks;
  const size_t alloc_size = total_bits / bits_per_word;
  return alloc_size * sizeof(Word);
}

//
// Launch the encode kernel
//
template<class Scalar>
size_t encode3launch(uint3 dims, 
                     const Scalar *d_data,
                     Word *stream,
                     const int bits_per_block)
{

  const int cuda_block_size = 128;
  dim3 block_size = dim3(cuda_block_size, 1, 1);

  uint3 zfp_pad(dims); 
  if(zfp_pad.x % 4 != 0) zfp_pad.x += 4 - dims.x % 4;
  if(zfp_pad.y % 4 != 0) zfp_pad.y += 4 - dims.y % 4;
  if(zfp_pad.z % 4 != 0) zfp_pad.z += 4 - dims.z % 4;

  const uint zfp_blocks = (zfp_pad.x * zfp_pad.y * zfp_pad.z) / 64; 

  //
  // we need to ensure that we launch a multiple of the 
  // cuda block size
  //
  int block_pad = 0; 
  if(zfp_blocks % cuda_block_size != 0)
  {
    block_pad = cuda_block_size - zfp_blocks % cuda_block_size; 
  }

  size_t total_blocks = block_pad + zfp_blocks;

  dim3 grid_size = calculate_grid_size(total_blocks, cuda_block_size);

  size_t stream_bytes = calc_device_mem3d(zfp_pad, bits_per_block);
  //ensure we start with 0s
  cudaMemset(stream, 0, stream_bytes);
  std::cout<<"Total blocks "<<zfp_blocks<<"\n";
  std::cout<<"Grid "<<grid_size.x<<" "<<grid_size.y<<" "<<grid_size.z<<"\n";
  std::cout<<"Block "<<block_size.x<<" "<<block_size.y<<" "<<block_size.z<<"\n";
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);

  cudaEventRecord(start);
	cudaEncode<Scalar> << <grid_size, block_size>> >
    (bits_per_block,
     d_data,
     stream,
     dims,
     zfp_pad,
     zfp_blocks);

  cudaEventRecord(stop);
  cudaEventSynchronize(stop);
  cudaStreamSynchronize(0);

  float miliseconds = 0;
  cudaEventElapsedTime(&miliseconds, start, stop);
  float seconds = miliseconds / 1000.f;
  printf("Encode elapsed time: %.5f (s)\n", seconds);
  float rate = (float(dims.x * dims.y * dims.z) * sizeof(Scalar) ) / seconds;
  rate /= 1024.f;
  rate /= 1024.f;
  printf("# encode3 rate: %.2f (MB / sec) %d\n", rate, bits_per_block);
  return stream_bytes;
}

//
// Just pass the raw pointer to the "real" encode
//
template<class Scalar>
size_t encode(uint3 dims, 
              Scalar *d_data,
              Word *stream,
              const int bits_per_block)
{
  return encode3launch<Scalar>(dims, d_data, stream, bits_per_block);
}

}
#endif
