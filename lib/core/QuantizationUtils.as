// Ported from draco.js core/QuantizationUtils.js (quantization_utils.h/cc).
// Decoder-only: the encoder-side Quantizer is not ported.

export class Dequantizer {
    // C++ computes delta as range / float(maxQuantizedValue) in float32; f32
    // arithmetic here matches the WASM decoder bit for bit.
    delta: f32 = 1.0;

    initFromRange(range: f32, maxQuantizedValue: i32): bool {
        if (maxQuantizedValue <= 0) {
            return false;
        }
        this.delta = range / <f32>maxQuantizedValue;
        return true;
    }
}
