// Ported from draco.js compression/entropy/ANSCoding.js
// (compression/entropy/ans.h). Asymmetric Numeral Systems (rANS),
// decode-only. http://arxiv.org/abs/1311.2540v2
//
// Arithmetic note: the Luau port computed the state update in float64 under
// the invariant quo * prob <= state < 2^30; here everything is genuine u32
// arithmetic, exact for the same reason.

export const ANS_P8_PRECISION: u32 = 256;
export const ANS_L_BASE: u32 = 4096;
const ANS_IO_BASE: u32 = 256;

function memGetLe16(buf: Uint8Array, offset: i32): u32 {
    return <u32>buf[offset] | (<u32>buf[offset + 1] << 8);
}

function memGetLe24(buf: Uint8Array, offset: i32): u32 {
    return <u32>buf[offset] | (<u32>buf[offset + 1] << 8) | (<u32>buf[offset + 2] << 16);
}

function memGetLe32(buf: Uint8Array, offset: i32): u32 {
    return <u32>buf[offset]
        | (<u32>buf[offset + 1] << 8)
        | (<u32>buf[offset + 2] << 16)
        | (<u32>buf[offset + 3] << 24);
}

// Simple decode state used by RAnsBitDecoder.
export class AnsDecoder {
    buf: Uint8Array = new Uint8Array(0);
    bufOffset: i32 = 0;
    state: u32 = 0;
}

// offset is the number of encoded bytes. Returns 0 on success, 1 on error.
export function ansReadInit(ans: AnsDecoder, buf: Uint8Array, offset: i32): i32 {
    if (offset < 1) {
        return 1;
    }
    ans.buf = buf;
    let x = <u32>buf[offset - 1] >> 6;
    if (x == 0) {
        ans.bufOffset = offset - 1;
        ans.state = <u32>buf[offset - 1] & 0x3F;
    } else if (x == 1) {
        if (offset < 2) {
            return 1;
        }
        ans.bufOffset = offset - 2;
        ans.state = memGetLe16(buf, offset - 2) & 0x3FFF;
    } else if (x == 2) {
        if (offset < 3) {
            return 1;
        }
        ans.bufOffset = offset - 3;
        ans.state = memGetLe24(buf, offset - 3) & 0x3FFFFF;
    } else {
        return 1;
    }
    ans.state += ANS_L_BASE;
    if (ans.state >= ANS_L_BASE * ANS_IO_BASE) {
        return 1;
    }
    return 0;
}

export function ansReadEnd(ans: AnsDecoder): bool {
    return ans.state == ANS_L_BASE;
}

export class RAnsDecoder {
    ransPrecisionBits: i32;
    ransPrecision: u32;
    ransPrecisionMask: u32;
    lRansBase: u32;
    // Fused per-rem entry: symbol | prob << 20 | cumProb << 41, one load in
    // the hot loop instead of three dependent ones.
    lutTable: Uint64Array = new Uint64Array(0);
    buf: Uint8Array = new Uint8Array(0);
    bufOffset: i32 = 0;
    state: u32 = 0;

    constructor(ransPrecisionBits: i32) {
        this.ransPrecisionBits = ransPrecisionBits;
        this.ransPrecision = <u32>1 << ransPrecisionBits;
        this.ransPrecisionMask = this.ransPrecision - 1;
        this.lRansBase = this.ransPrecision * 4;
    }

    // offset is the number of bytes encoded. Returns 0 on success, non-zero
    // on error.
    readInit(buf: Uint8Array, offset: i32): i32 {
        if (offset < 1) {
            return 1;
        }
        this.buf = buf;
        let x = <u32>buf[offset - 1] >> 6;
        if (x == 0) {
            this.bufOffset = offset - 1;
            this.state = <u32>buf[offset - 1] & 0x3F;
        } else if (x == 1) {
            if (offset < 2) {
                return 1;
            }
            this.bufOffset = offset - 2;
            this.state = memGetLe16(buf, offset - 2) & 0x3FFF;
        } else if (x == 2) {
            if (offset < 3) {
                return 1;
            }
            this.bufOffset = offset - 3;
            this.state = memGetLe24(buf, offset - 3) & 0x3FFFFF;
        } else if (x == 3) {
            if (offset < 4) {
                return 1;
            }
            this.bufOffset = offset - 4;
            this.state = memGetLe32(buf, offset - 4) & 0x3FFFFFFF;
        } else {
            return 1;
        }
        this.state += this.lRansBase;
        if (this.state >= this.lRansBase * ANS_IO_BASE) {
            return 1;
        }
        return 0;
    }

    readEnd(): bool {
        return this.state == this.lRansBase;
    }

    ransRead(): u32 {
        let buf = this.buf;
        let lRansBase = this.lRansBase;
        let state = this.state;
        let bufOffset = this.bufOffset;
        while (state < lRansBase && bufOffset > 0) {
            bufOffset--;
            state = (state << 8) | <u32>buf[bufOffset];
        }
        let quo = state >> this.ransPrecisionBits;
        let rem = state & this.ransPrecisionMask;
        let entry = unchecked(this.lutTable[rem]);
        let symbol = <u32>(entry & 0xFFFFF);
        let prob = <u32>((entry >> 20) & 0x1FFFFF);
        let cumProb = <u32>(entry >> 41);
        this.state = quo * prob + rem - cumProb;
        this.bufOffset = bufOffset;
        return symbol;
    }

    // Batch ransRead() into out[0..count). Hot loop: raw loads/stores off the
    // view data pointers -- this is the single hottest loop in the decoder.
    unsafe decodeSymbols(out: Uint32Array, count: i32): void {
        let lRansBase = this.lRansBase;
        let ransPrecisionBits = this.ransPrecisionBits;
        let ransPrecisionMask = this.ransPrecisionMask;

        let bufPtr = this.buf.dataStart;
        let lutPtr = this.lutTable.dataStart;
        let outPtr = out.dataStart;

        let state = this.state;
        let bufOffset = this.bufOffset;
        for (let i = 0; i < count; i++) {
            while (state < lRansBase && bufOffset > 0) {
                bufOffset--;
                state = (state << 8) | <u32>load<u8>(bufPtr + <usize>bufOffset);
            }
            let rem = state & ransPrecisionMask;
            let entry = load<u64>(lutPtr + (<usize>rem << 3));
            let symbol = <u32>(entry & 0xFFFFF);
            store<u32>(outPtr + (<usize>i << 2), symbol);
            state = (state >> ransPrecisionBits) * <u32>((entry >> 20) & 0x1FFFFF)
                + rem - <u32>(entry >> 41);
        }
        this.state = state;
        this.bufOffset = bufOffset;
    }

    // Builds the ransPrecision-entry lookup table. Returns false on bad input
    // data.
    ransBuildLookUpTable(tokenProbs: Uint32Array, numSymbols: i32): bool {
        let lutTable = new Uint64Array(<i32>this.ransPrecision);
        this.lutTable = lutTable;
        let cumProb: u32 = 0;
        let actProb: u32 = 0;
        for (let i = 0; i < numSymbols; i++) {
            let prob = tokenProbs[i];
            cumProb += prob;
            if (cumProb > this.ransPrecision) {
                return false;
            }
            let entry = <u64>i | (<u64>prob << 20) | (<u64>actProb << 41);
            for (let j = actProb; j < cumProb; j++) {
                unchecked(lutTable[<i32>j] = entry);
            }
            actProb = cumProb;
        }
        if (cumProb != this.ransPrecision) {
            return false;
        }
        return true;
    }
}
