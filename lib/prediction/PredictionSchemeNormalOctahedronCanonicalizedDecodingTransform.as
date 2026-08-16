// Ported from draco prediction_scheme_normal_octahedron_transform_base.h,
// prediction_scheme_normal_octahedron_canonicalized_transform_base.h and
// prediction_scheme_normal_octahedron_canonicalized_decoding_transform.h,
// monomorphized for DataTypeT = int32_t (the only C++ instantiation used).
// The plain (non-canonicalized) octahedron decoding transform exists only
// behind DRACO_BACKWARDS_COMPATIBILITY_SUPPORTED and is not ported.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PredictionSchemeTransformType } from "../config/CompressionShared";
import { OctahedronToolBox } from "../attributes/NormalCompressionUtils";

// C++ MostSignificantBit (core/bit_utils.h); callers guarantee n != 0.
function mostSignificantBit(n: u32): i32 {
    return 31 - <i32>clz<u32>(n);
}

// Shared functionality of the octahedral normal transforms
// (PredictionSchemeNormalOctahedronTransformBase).
export class PredictionSchemeNormalOctahedronTransformBase {
    protected octahedronToolBox: OctahedronToolBox = new OctahedronToolBox();
    // Scratch for the tool box's two-component outputs.
    protected tmpPoint: Int32Array = new Int32Array(2);

    getType(): i32 {
        return PredictionSchemeTransformType.PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON;
    }

    // Corrections stay positive.
    areCorrectionsPositive(): bool {
        return true;
    }

    maxQuantizedValue(): i32 {
        return this.octahedronToolBox.maxQuantizedValue();
    }

    centerValue(): i32 {
        return this.octahedronToolBox.centerValue();
    }

    quantizationBits(): i32 {
        return this.octahedronToolBox.quantizationBits();
    }

    // The mod value is expected to be of the form 2^b-1.
    protected setMaxQuantizedValue(maxQuantizedValue: i32): bool {
        if (maxQuantizedValue % 2 == 0) {
            return false;
        }
        let q = mostSignificantBit(<u32>maxQuantizedValue) + 1;
        return this.octahedronToolBox.setQuantizationBits(q);
    }
}

export class PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform
    extends PredictionSchemeNormalOctahedronTransformBase {

    getType(): i32 {
        return PredictionSchemeTransformType.PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON_CANONICALIZED;
    }

    // Dummy to fulfill the transform concept.
    init(numComponents: i32): void {}

    // Canonicalized transform base helpers.

    getRotationCount(sX: i32, sY: i32): i32 {
        let rotationCount = 0;
        if (sX == 0) {
            if (sY == 0) {
                rotationCount = 0;
            } else if (sY > 0) {
                rotationCount = 3;
            } else {
                rotationCount = 1;
            }
        } else if (sX > 0) {
            if (sY >= 0) {
                rotationCount = 2;
            } else {
                rotationCount = 1;
            }
        } else {
            if (sY <= 0) {
                rotationCount = 0;
            } else {
                rotationCount = 3;
            }
        }
        return rotationCount;
    }

    // Writes the rotated point to out[0], out[1].
    rotatePoint(x: i32, y: i32, rotationCount: i32, out: Int32Array): void {
        if (rotationCount == 1) {
            out[0] = y;
            out[1] = -x;
        } else if (rotationCount == 2) {
            out[0] = -x;
            out[1] = -y;
        } else if (rotationCount == 3) {
            out[0] = -y;
            out[1] = x;
        } else {
            out[0] = x;
            out[1] = y;
        }
    }

    isInBottomLeft(x: i32, y: i32): bool {
        if (x == 0 && y == 0) {
            return true;
        }
        return x < 0 && y <= 0;
    }

    decodeTransformData(buffer: DecoderBuffer): bool {
        let maxQuantizedValue = buffer.decodeInt32();
        if (buffer.err) {
            return false;
        }
        // The center value is carried by the stream but implied by the max
        // quantized value.
        buffer.decodeInt32();
        if (buffer.err) {
            return false;
        }
        if (!this.setMaxQuantizedValue(maxQuantizedValue)) {
            return false;
        }
        // Guard against values read from a malformed stream.
        if (this.quantizationBits() < 2 || this.quantizationBits() > 30) {
            return false;
        }
        return true;
    }

    computeOriginalValue(
        predVals: Int32Array, predOffset: i32,
        corrVals: Int32Array, corrOffset: i32,
        outOrigVals: Int32Array, outOffset: i32): void {
        let toolBox = this.octahedronToolBox;
        let t = toolBox.centerValue();

        let predX = predVals[predOffset];
        let predY = predVals[predOffset + 1];
        let corrX = corrVals[corrOffset];
        let corrY = corrVals[corrOffset + 1];

        predX = predX - t;
        predY = predY - t;
        let predIsInDiamond = toolBox.isInDiamond(predX, predY);
        if (!predIsInDiamond) {
            toolBox.invertDiamond(predX, predY, this.tmpPoint);
            predX = this.tmpPoint[0];
            predY = this.tmpPoint[1];
        }
        let predIsInBottomLeft = this.isInBottomLeft(predX, predY);
        let rotationCount = this.getRotationCount(predX, predY);
        if (!predIsInBottomLeft) {
            this.rotatePoint(predX, predY, rotationCount, this.tmpPoint);
            predX = this.tmpPoint[0];
            predY = this.tmpPoint[1];
        }
        // i32 addition wraps like the C++ AddAsUnsigned.
        let origX = toolBox.modMax(predX + corrX);
        let origY = toolBox.modMax(predY + corrY);
        if (!predIsInBottomLeft) {
            let reverseRotationCount = (4 - rotationCount) % 4;
            this.rotatePoint(origX, origY, reverseRotationCount, this.tmpPoint);
            origX = this.tmpPoint[0];
            origY = this.tmpPoint[1];
        }
        if (!predIsInDiamond) {
            toolBox.invertDiamond(origX, origY, this.tmpPoint);
            origX = this.tmpPoint[0];
            origY = this.tmpPoint[1];
        }
        outOrigVals[outOffset] = origX + t;
        outOrigVals[outOffset + 1] = origY + t;
    }
}
