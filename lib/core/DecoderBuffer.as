// Ported from draco.js core/DecoderBuffer.js (decoder_buffer.h/cc) via the
// Luau port. Multi-byte reads are little-endian load<T>s on the backing
// ArrayBuffer at (base + pos); wasm linear memory is little-endian, matching
// the DataView littleEndian:true reads.
//
// Error protocol: the Luau port returned nil on a failed read. Numeric returns
// cannot be nullable here, so failed reads return 0 and set the sticky `err`
// flag (cleared by init). Reference-returning decodeBytes returns null and
// also sets `err`.

// Macros.bitstreamVersion(2, 2).
const VERSION_2_2: i32 = 0x0202;

// Reads up to 32 bits at a time from a bit-packed sub-buffer (LSB first).
export class BitDecoder {
    buf: ArrayBuffer = new ArrayBuffer(0);
    base: i32 = 0;
    bitOffset: i32 = 0;
    byteLength: i32 = 0;
    err: bool = false;

    reset(u8: Uint8Array, byteLength: i32): void {
        this.resetRaw(u8.buffer, u8.byteOffset, byteLength);
    }

    // View-free reset so startBitDecoding does not allocate a subarray.
    resetRaw(buf: ArrayBuffer, base: i32, byteLength: i32): void {
        this.buf = buf;
        this.base = base;
        this.byteLength = byteLength;
        this.bitOffset = 0;
        this.err = false;
    }

    bitsDecoded(): i32 {
        return this.bitOffset;
    }

    unsafe getBits(nbits: i32): u32 {
        if (nbits > 32) {
            this.err = true;
            return 0;
        }
        let p = changetype<usize>(this.buf) + <usize>this.base;
        let off = this.bitOffset;
        let byteOffset = off >> 3;
        let bitShift = off & 7;

        // Fast path: enough bytes remain to read 32 bits safely.
        if (byteOffset + 4 < this.byteLength) {
            let val = load<u32>(p + <usize>byteOffset);
            let result: u32;
            if (nbits > 32 - bitShift) {
                let val2 = <u32>load<u8>(p + <usize>(byteOffset + 4));
                result = (val >> bitShift) | (val2 << (32 - bitShift));
            } else {
                result = val >> bitShift;
            }

            this.bitOffset = off + nbits;
            if (nbits == 32) {
                return result;
            }
            return result & ((<u32>1 << nbits) - 1);
        }

        // Safe fallback path near the end of the buffer.
        let value: u32 = 0;
        let bitsRead = 0;
        let currOff = off;
        while (bitsRead < nbits) {
            let bOff = currOff >> 3;
            if (bOff >= this.byteLength) {
                break;
            }
            let bShift = currOff & 7;
            let bitsAvail = 8 - bShift;
            let bitsNeeded = nbits - bitsRead;
            let bitsToRead = bitsAvail < bitsNeeded ? bitsAvail : bitsNeeded;
            let mask = ((<u32>1) << bitsToRead) - 1;
            let byteVal = <u32>load<u8>(p + <usize>bOff);
            value |= ((byteVal >> bShift) & mask) << bitsRead;
            bitsRead += bitsToRead;
            currOff += bitsToRead;
        }
        this.bitOffset = currOff;
        return value;
    }
}

export class DecoderBuffer {
    buf: ArrayBuffer = new ArrayBuffer(0);
    base: i32 = 0;
    dataSize: i32 = 0;
    pos: i32 = 0;
    bitDecoder: BitDecoder = new BitDecoder();
    bitMode: bool = false;
    bitstreamVersion: i32 = 0;
    err: bool = false;
    private dataView: Uint8Array = new Uint8Array(0);

    // dataSize < 0 means the whole buffer; version < 0 keeps the current one.
    init(data: ArrayBuffer, dataSize: i32 = -1, version: i32 = -1): void {
        this.buf = data;
        this.base = 0;
        this.dataSize = dataSize >= 0 ? dataSize : data.byteLength;
        this.pos = 0;
        this.err = false;
        this.bitMode = false;
        if (version >= 0) {
            this.bitstreamVersion = version;
        }
        this.dataView = Uint8Array.wrap(this.buf, 0, this.dataSize);
    }

    // Init from an existing view (no copy), like the JS Uint8Array path.
    initView(data: Uint8Array, dataSize: i32 = -1, version: i32 = -1): void {
        this.buf = data.buffer;
        this.base = data.byteOffset;
        this.dataSize = dataSize >= 0 ? dataSize : data.length;
        this.pos = 0;
        this.err = false;
        this.bitMode = false;
        if (version >= 0) {
            this.bitstreamVersion = version;
        }
        this.dataView = Uint8Array.wrap(this.buf, this.base, this.dataSize);
    }

    private unsafe head(): usize {
        return changetype<usize>(this.buf) + <usize>(this.base + this.pos);
    }

    unsafe decodeUint8(): u32 {
        if (this.pos + 1 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = <u32>load<u8>(this.head());
        this.pos += 1;
        return val;
    }

    unsafe decodeInt8(): i32 {
        if (this.pos + 1 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = <i32>load<i8>(this.head());
        this.pos += 1;
        return val;
    }

    unsafe decodeUint16(): u32 {
        if (this.pos + 2 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = <u32>load<u16>(this.head());
        this.pos += 2;
        return val;
    }

    unsafe decodeUint32(): u32 {
        if (this.pos + 4 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = load<u32>(this.head());
        this.pos += 4;
        return val;
    }

    unsafe decodeInt32(): i32 {
        if (this.pos + 4 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = load<i32>(this.head());
        this.pos += 4;
        return val;
    }

    unsafe decodeFloat32(): f32 {
        if (this.pos + 4 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = load<f32>(this.head());
        this.pos += 4;
        return val;
    }

    unsafe decodeUint64(): u64 {
        if (this.pos + 8 > this.dataSize) {
            this.err = true;
            return 0;
        }
        let val = load<u64>(this.head());
        this.pos += 8;
        return val;
    }

    unsafe decodeBytes(size: i32): Uint8Array | null {
        if (this.pos + size > this.dataSize) {
            this.err = true;
            return null;
        }
        let out = new Uint8Array(size);
        memory.copy(out.dataStart, this.head(), <usize>size);
        this.pos += size;
        return out;
    }

    // Unsigned varint, MSB continuation coding (LEB128). Lives here rather
    // than in VarintDecoding so the two modules need no import cycle.
    decodeVarintU64(): u64 {
        let value: u64 = 0;
        let shift = 0;
        for (let i = 0; i < 10; i++) {
            let byte = this.decodeUint8();
            if (this.err) {
                return 0;
            }
            value |= <u64>(byte & 0x7F) << shift;
            if ((byte & 0x80) == 0) {
                return value;
            }
            shift += 7;
        }
        // No terminator within maxBytes.
        this.err = true;
        return 0;
    }

    decodeVarintUint32(): u32 {
        return <u32>this.decodeVarintU64();
    }

    decodeVarintUint64(): u64 {
        return this.decodeVarintU64();
    }

    // Returns the decoded sub-buffer size (0 when decodeSize is false).
    startBitDecoding(decodeSize: bool): u64 {
        let outSize: u64 = 0;
        if (decodeSize) {
            if (this.bitstreamVersion < VERSION_2_2) {
                outSize = this.decodeUint64();
            } else {
                outSize = this.decodeVarintU64();
            }
            if (this.err) {
                return 0;
            }
        }
        this.bitMode = true;
        this.bitDecoder.resetRaw(this.buf, this.base + this.pos, this.dataSize - this.pos);
        return outSize;
    }

    endBitDecoding(): void {
        this.bitMode = false;
        let bitsDecoded = this.bitDecoder.bitsDecoded();
        let bytesDecoded = (bitsDecoded + 7) >> 3;
        this.pos += bytesDecoded;
    }

    decodeLeastSignificantBits32(nbits: i32): u32 {
        if (!this.bitMode) {
            this.err = true;
            return 0;
        }
        let val = this.bitDecoder.getBits(nbits);
        if (this.bitDecoder.err) {
            this.err = true;
        }
        return val;
    }

    advance(bytes: i32): void {
        this.pos += bytes;
    }

    data(): Uint8Array {
        return this.dataView;
    }

    dataHead(): Uint8Array {
        return Uint8Array.wrap(this.buf, this.base + this.pos, this.dataSize - this.pos);
    }

    remainingSize(): i32 {
        return this.dataSize - this.pos;
    }

    decodedSize(): i32 {
        return this.pos;
    }

    bitDecoderActive(): bool {
        return this.bitMode;
    }
}

export function newDecoderBuffer(): DecoderBuffer {
    return new DecoderBuffer();
}
