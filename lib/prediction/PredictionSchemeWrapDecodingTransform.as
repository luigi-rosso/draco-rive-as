// Ported from draco prediction_scheme_wrap_transform_base.h +
// prediction_scheme_wrap_decoding_transform.h, monomorphized for the only C++
// instantiation the decoder subset uses: DataTypeT = CorrTypeT = int32_t.
//
// Stored corrections are wrapped around the original value bounds centered at
// 0; the decoder unwraps any corrected value that falls out of [min, max].

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PredictionSchemeTransformType } from "../config/CompressionShared";

export class PredictionSchemeWrapDecodingTransform {
    private numComponents: i32 = 0;
    private minValue: i32 = 0;
    private maxValue: i32 = 0;
    private maxDif: i32 = 0;

    getType(): i32 {
        return PredictionSchemeTransformType.PREDICTION_TRANSFORM_WRAP;
    }

    init(numComponents: i32): void {
        this.numComponents = numComponents;
    }

    areCorrectionsPositive(): bool {
        return false;
    }

    // Unused for the wrap transform (only the octahedral transforms carry it).
    quantizationBits(): i32 {
        return -1;
    }

    // Computes original values from the predicted values and the decoded
    // corrections, unwrapping out-of-bounds results.
    computeOriginalValue(
        predictedVals: Int32Array, predictedOffset: i32,
        corrVals: Int32Array, corrOffset: i32,
        outOriginalVals: Int32Array, outOffset: i32): void {
        let nc = this.numComponents;
        let minValue = this.minValue;
        let maxValue = this.maxValue;
        let maxDif = this.maxDif;
        for (let i = 0; i < nc; i++) {
            // C++ clamps the prediction first (ClampPredictedValue).
            let pred = unchecked(predictedVals[predictedOffset + i]);
            if (pred > maxValue) {
                pred = maxValue;
            } else if (pred < minValue) {
                pred = minValue;
            }
            // i32 addition wraps like the C++ unsigned-add reinterpretation.
            let orig: i32 = pred + unchecked(corrVals[corrOffset + i]);
            if (orig > maxValue) {
                orig -= maxDif;
            } else if (orig < minValue) {
                orig += maxDif;
            }
            unchecked(outOriginalVals[outOffset + i] = orig);
        }
    }

    decodeTransformData(buffer: DecoderBuffer): bool {
        let minValue = buffer.decodeInt32();
        if (buffer.err) {
            return false;
        }
        let maxValue = buffer.decodeInt32();
        if (buffer.err) {
            return false;
        }
        if (minValue > maxValue) {
            return false;
        }
        this.minValue = minValue;
        this.maxValue = maxValue;
        return this.initCorrectionBounds();
    }

    private initCorrectionBounds(): bool {
        let dif = <i64>this.maxValue - <i64>this.minValue;
        if (dif < 0 || dif >= <i64>i32.MAX_VALUE) {
            return false;
        }
        this.maxDif = 1 + <i32>dif;
        return true;
    }
}
