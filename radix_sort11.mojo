from memory import memset_zero, memcpy, stack_allocation
from memory.unsafe import bitcast
from vec import print_v
from sys.intrinsics import PrefetchOptions

@always_inline
fn _float_flip(f: UInt32) -> UInt32:
    let mask = bitcast[DType.uint32, 1](-bitcast[DType.int32, 1](f >> 31) | 0x80_00_00_00)
    return f ^ mask

@always_inline
fn _float_flip_x(inout f: UInt32):
    let mask = bitcast[DType.uint32, 1](-bitcast[DType.int32, 1](f >> 31) | 0x80_00_00_00)
    f ^= mask

@always_inline
fn _inverse_float_flip(f: UInt32) -> UInt32:
    let mask = ((f >> 31) - 1) | 0x80_00_00_00
    return f ^ mask

@always_inline
fn _0(v: UInt32) -> Int:
    return (v & 0x7ff).to_int()

@always_inline
fn _1(v: UInt32) -> Int:
    return (v >> 11 & 0x7ff).to_int()

@always_inline
fn _2(v: UInt32) -> Int:
    return (v >> 22).to_int()


# based on http://stereopsis.com/radix.html
fn radix_sort11(inout vector: DynamicVector[Float32]):
    let elements = len(vector)
    let array = Buffer[Dim(1), DType.uint32](DTypePointer[DType.uint32](vector.data.bitcast[UInt32]()), elements)
    let sorted = Buffer[Dim(1), DType.uint32](DTypePointer[DType.uint32].aligned_alloc(4, elements))
    alias histogram_size = 2048
    let histogram1 = stack_allocation[histogram_size * 3, DType.uint32]()
    memset_zero(histogram1, histogram_size * 3)

    let histogram2 = histogram1.offset(histogram_size)
    let histogram3 = histogram2.offset(histogram_size)

    for i in range(elements):
        # TODO: Prefetch
        # array.prefetch[PrefetchOptions().to_data_cache()](i+64)
        let fi = _float_flip(array[i])
        let i1 = _0(fi)
        let i2 = _1(fi)
        let i3 = _2(fi)
        
        let p1 = histogram1.offset(i1)
        let p2 = histogram2.offset(i2)
        let p3 = histogram3.offset(i3)

        # SIMD is a bit slower
        # let fi = _float_flip(array[i])
        # var fiv = SIMD[DType.uint32, 2](fi)
        # fiv >>= SIMD[DType.uint32, 2](0, 11, 22, 0)
        # fiv &= SIMD[DType.uint32, 2](0x7ff, 0x7ff, 0xffff, 0)

        # let p1 = histogram1.offset(fiv[0].to_int())
        # let p2 = histogram2.offset(fiv[1].to_int())
        # let p3 = histogram3.offset((fi >> 22).to_int())

        p1.store(p1.load() + 1)
        p2.store(p2.load() + 1)
        p3.store(p3.load() + 1)

    # for i in range(histogram_size):
    #     print(histogram1.offset(i).load(), histogram2.offset(i).load(), histogram3.offset(i).load())

    var sum1: UInt32 = 0 
    var sum2: UInt32 = 0
    var sum3: UInt32 = 0
    var tsum: UInt32 = 0

    for i in range(histogram_size):
        let p1 = histogram1.offset(i)
        let p2 = histogram2.offset(i)
        let p3 = histogram3.offset(i)

        tsum = p1.load() + sum1
        p1.store(sum1 - 1)
        sum1 = tsum

        tsum = p2.load() + sum2
        p2.store(sum2 - 1)
        sum2 = tsum

        tsum = p3.load() + sum3
        p3.store(sum3 - 1)
        sum3 = tsum

    for i in range(elements):
        var fi = array[i]
        _float_flip_x(fi)
        let p1 = histogram1.offset(_0(fi))
        let index = p1.load() + 1
        p1.store(index)
        sorted[index.to_int()] = fi

    for i in range(elements):
        let si = sorted[i]
        let pos = _1(si)
        let p2 = histogram2.offset(pos)
        let index = p2.load() + 1
        p2.store(index)
        array[index.to_int()] = si

    for i in range(elements):
        let ai = array[i]
        let pos = _2(ai)
        let p3 = histogram3.offset(pos)
        let index = p3.load() + 1
        p3.store(index)
        sorted[index.to_int()] = _inverse_float_flip(ai)

    memcpy(vector.data, sorted.data.bitcast[DType.float32](), elements)
    sorted.data.free()

fn main():
    var v3 = DynamicVector[Float32]()
    v3.push_back(0)
    v3.push_back(-23)
    v3.push_back(123)
    v3.push_back(-48)
    v3.push_back(-48.1)
    v3.push_back(48.111)
    v3.push_back(48.101)
    v3.push_back(48.10111)
    v3.push_back(-0.10111)
    v3.push_back(0.10111)
    print_v[DType.float32](v3)

    radix_sort11(v3)
    print_v[DType.float32](v3)