// Ported from draco.js compression/entropy/SymbolDecoding.js
// (compression/entropy/symbol_decoding.h/cc).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { RAnsSymbolDecoder } from "./RAnsSymbolDecoder";
import { SymbolCodingMethod } from "../config/CompressionShared";

function decodeTaggedSymbols(
    numValues: i32, numComponents: i32, srcBuffer: DecoderBuffer,
    outValues: Uint32Array): bool {
    let tagDecoder = new RAnsSymbolDecoder(5);
    if (!tagDecoder.create(srcBuffer)) {
        return false;
    }

    if (!tagDecoder.startDecoding(srcBuffer)) {
        return false;
    }

    if (numValues > 0 && tagDecoder.numSymbols() == 0) {
        return false;
    }

    srcBuffer.startBitDecoding(false);
    // After startBitDecoding(false) the buffer is in bit mode; read bits
    // straight from the bit decoder, skipping the per-component dispatch
    // wrapper.
    let bd = srcBuffer.bitDecoder;
    let tagAns = tagDecoder.ans;
    let valueId = 0;
    let i = 0;
    while (i < numValues) {
        let bitLength = tagAns.ransRead();
        for (let c = 0; c < numComponents; c++) {
            let val = bd.getBits(<i32>bitLength);
            if (bd.err) {
                return false;
            }
            outValues[valueId] = val;
            valueId += 1;
        }
        i += numComponents;
    }
    tagDecoder.endDecoding();
    srcBuffer.endBitDecoding();
    return true;
}

function decodeRawSymbolsInternal(
    uniqueSymbolsBitLength: i32, numValues: i32, srcBuffer: DecoderBuffer,
    outValues: Uint32Array): bool {
    let decoder = new RAnsSymbolDecoder(uniqueSymbolsBitLength);
    if (!decoder.create(srcBuffer)) {
        return false;
    }

    if (numValues > 0 && decoder.numSymbols() == 0) {
        return false;
    }

    if (!decoder.startDecoding(srcBuffer)) {
        return false;
    }
    decoder.ans.decodeSymbols(outValues, numValues);
    decoder.endDecoding();
    return true;
}

function decodeRawSymbols(numValues: i32, srcBuffer: DecoderBuffer, outValues: Uint32Array): bool {
    let maxBitLength = srcBuffer.decodeUint8();
    if (srcBuffer.err) {
        return false;
    }
    if (maxBitLength < 1 || maxBitLength > 18) {
        return false;
    }
    return decodeRawSymbolsInternal(<i32>maxBitLength, numValues, srcBuffer, outValues);
}

// Decodes numValues entropy-coded symbols into outValues (Uint32Array).
// numComponents is used for tagged coding. Returns false on error.
export function decodeSymbols(
    numValues: i32, numComponents: i32, srcBuffer: DecoderBuffer,
    outValues: Uint32Array): bool {
    if (numValues == 0) {
        return true;
    }
    let scheme = srcBuffer.decodeUint8();
    if (srcBuffer.err) {
        return false;
    }
    if (scheme == <u32>SymbolCodingMethod.SYMBOL_CODING_TAGGED) {
        return decodeTaggedSymbols(numValues, numComponents, srcBuffer, outValues);
    } else if (scheme == <u32>SymbolCodingMethod.SYMBOL_CODING_RAW) {
        return decodeRawSymbols(numValues, srcBuffer, outValues);
    }
    return false;
}
