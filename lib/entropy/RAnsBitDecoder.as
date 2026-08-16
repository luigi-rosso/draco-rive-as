// Ported from draco.js compression/bit_coders/RAnsBitDecoder.js
// (compression/bit_coders/rans_bit_decoder.h/cc). Decodes bits encoded with
// RAnsBitEncoder.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { AnsDecoder, ansReadInit, ansReadEnd, ANS_L_BASE, ANS_P8_PRECISION } from "./ANSCoding";

export class RAnsBitDecoder {
    ansDecoder: AnsDecoder = new AnsDecoder();
    probZero: u32 = 0;
    // ANS_P8_PRECISION - probZero, precomputed.
    p: u32 = 0;

    // Returns false when the data is invalid.
    startDecoding(sourceBuffer: DecoderBuffer): bool {
        this.clear();

        let probZero = sourceBuffer.decodeUint8();
        if (sourceBuffer.err) {
            return false;
        }
        this.probZero = probZero;
        this.p = ANS_P8_PRECISION - probZero;

        let sizeInBytes = sourceBuffer.decodeVarintUint32();
        if (sourceBuffer.err) {
            return false;
        }

        if (sizeInBytes > <u32>sourceBuffer.remainingSize()) {
            return false;
        }

        let dataHead = sourceBuffer.dataHead();
        if (ansReadInit(this.ansDecoder, dataHead, <i32>sizeInBytes) != 0) {
            return false;
        }
        sourceBuffer.advance(<i32>sizeInBytes);
        return true;
    }

    decodeNextBit(): bool {
        let ans = this.ansDecoder;
        let p = this.p;
        if (ans.state < ANS_L_BASE && ans.bufOffset > 0) {
            ans.bufOffset--;
            ans.state = (ans.state << 8) | <u32>unchecked(ans.buf[ans.bufOffset]);
        }
        let x = ans.state;
        let quot = x >> 8;
        let rem = x & 0xFF;
        let xn = quot * p;
        if (rem < p) {
            ans.state = xn + rem;
            return true;
        }
        ans.state = x - xn - p;
        return false;
    }

    endDecoding(): void {}

    clear(): void {
        ansReadEnd(this.ansDecoder);
    }
}
