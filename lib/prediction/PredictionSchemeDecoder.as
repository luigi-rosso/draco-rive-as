// Ported from draco prediction_scheme_decoder.h /
// prediction_scheme_decoder_interface.h, monomorphized for DataTypeT =
// CorrTypeT = int32_t (the only combination the decoder subset instantiates).
// The transform lives on the concrete subclasses since each pairs with exactly
// one transform type.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "../attributes/PointAttribute";
import { GeometryAttributeType } from "../attributes/GeometryAttribute";
import {
    PredictionSchemeMethod,
    PredictionSchemeTransformType,
} from "../config/CompressionShared";

export abstract class PredictionSchemeDecoder {
    protected attribute: PointAttribute?;

    constructor(attribute: PointAttribute?) {
        this.attribute = attribute;
    }

    getAttribute(): PointAttribute? {
        return this.attribute;
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.PREDICTION_NONE;
    }

    getTransformType(): i32 {
        return PredictionSchemeTransformType.PREDICTION_TRANSFORM_NONE;
    }

    isInitialized(): bool {
        return true;
    }

    // Number of parent attributes needed for the prediction.
    getNumParentAttributes(): i32 {
        return 0;
    }

    getParentAttributeType(i: i32): i32 {
        return GeometryAttributeType.INVALID;
    }

    // Returns false when the attribute does not meet the scheme requirements.
    setParentAttribute(att: PointAttribute): bool {
        return false;
    }

    areCorrectionsPositive(): bool {
        return false;
    }

    // Decodes prediction scheme specific data from the input buffer.
    decodePredictionData(buffer: DecoderBuffer): bool {
        return false;
    }

    // Reverts the prediction applied during encoding. |entryToPointIdMap| maps
    // value entries to point ids of the associated point cloud.
    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        return false;
    }
}
