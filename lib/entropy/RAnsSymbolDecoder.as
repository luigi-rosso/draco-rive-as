// Ported from draco.js compression/entropy/RAnsSymbolDecoder.js
// (compression/entropy/rans_symbol_decoder.h).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { RAnsDecoder } from "./ANSCoding";

// rANS precision for the given unique-symbols bit length, clamped to [12, 20].
export function computeRAnsPrecisionFromUniqueSymbolsBitLength(symbolsBitLength: i32): i32 {
    let unclamped = (3 * symbolsBitLength) / 2;
    if (unclamped < 12) {
        return 12;
    }
    if (unclamped > 20) {
        return 20;
    }
    return unclamped;
}

export class RAnsSymbolDecoder {
    uniqueSymbolsBitLength: i32;
    ransPrecisionBits: i32;
    ransPrecision: u32;
    probabilityTable: Uint32Array = new Uint32Array(0);
    numSymbols_: u32 = 0;
    ans: RAnsDecoder;

    constructor(uniqueSymbolsBitLength: i32) {
        this.uniqueSymbolsBitLength = uniqueSymbolsBitLength;
        this.ransPrecisionBits =
            computeRAnsPrecisionFromUniqueSymbolsBitLength(uniqueSymbolsBitLength);
        this.ransPrecision = <u32>1 << this.ransPrecisionBits;
        this.ans = new RAnsDecoder(this.ransPrecisionBits);
    }

    numSymbols(): u32 {
        return this.numSymbols_;
    }

    // Initialize the decoder and decode the probability table.
    create(srcBuffer: DecoderBuffer): bool {
        if (srcBuffer.bitstreamVersion == 0) {
            return false;
        }

        let val = srcBuffer.decodeVarintUint32();
        if (srcBuffer.err) {
            return false;
        }
        this.numSymbols_ = val;

        // Reject an unreasonably high symbol count.
        if (<i32>(this.numSymbols_ / 64) > srcBuffer.remainingSize()) {
            return false;
        }

        let numSymbols = <i32>this.numSymbols_;
        let probabilityTable = new Uint32Array(numSymbols);
        this.probabilityTable = probabilityTable;
        if (numSymbols == 0) {
            return true;
        }

        // Read via a local cursor instead of a decodeUint8() call per byte.
        let data = srcBuffer.data();
        let startPos = srcBuffer.decodedSize();
        let endPos = startPos + srcBuffer.remainingSize();
        let pos = startPos;
        let i = 0;
        while (i < numSymbols) {
            if (pos >= endPos) {
                return false;
            }
            let probData = <u32>data[pos];
            pos += 1;

            // Low 2 bits = token: 0-2 extra-byte count, 3 = run-length of
            // zero-prob entries.
            let token = probData & 3;
            if (token == 3) {
                let offset = probData >> 2;
                if (i + <i32>offset >= numSymbols) {
                    return false;
                }
                // The run's probabilities stay 0; the fresh table already is.
                i += <i32>offset;
            } else {
                let extraBytes = <i32>token;
                let prob = probData >> 2;
                for (let b = 0; b < extraBytes; b++) {
                    if (pos >= endPos) {
                        return false;
                    }
                    // Shift 8 bits per extra byte, minus 2 for the two token
                    // bits.
                    prob |= <u32>data[pos] << (8 * (b + 1) - 2);
                    pos += 1;
                }
                probabilityTable[i] = prob;
            }
            i += 1;
        }
        srcBuffer.advance(pos - startPos);

        if (!this.ans.ransBuildLookUpTable(this.probabilityTable, numSymbols)) {
            return false;
        }
        return true;
    }

    // Starts decoding, advancing buffer past the encoded data.
    startDecoding(srcBuffer: DecoderBuffer): bool {
        let bytesEncoded = srcBuffer.decodeVarintUint64();
        if (srcBuffer.err) {
            return false;
        }

        if (bytesEncoded > <u64>srcBuffer.remainingSize()) {
            return false;
        }

        let dataHead = srcBuffer.dataHead();
        srcBuffer.advance(<i32>bytesEncoded);
        if (this.ans.readInit(dataHead, <i32>bytesEncoded) != 0) {
            return false;
        }
        return true;
    }

    endDecoding(): void {
        this.ans.readEnd();
    }
}
