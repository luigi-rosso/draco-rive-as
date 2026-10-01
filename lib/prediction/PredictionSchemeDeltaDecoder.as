// Ported from draco prediction_scheme_delta_decoder.h. Two monomorphized
// variants replace the TransformT parameter: DeltaDecoderWrap for integer
// attributes and DeltaDecoderNormalOcta for the normals fallback when a
// mesh prediction scheme is unavailable (both i32).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "../attributes/PointAttribute";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "./PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";

export class PredictionSchemeDeltaDecoderWrap extends PredictionSchemeDecoder {
    private transform: PredictionSchemeWrapDecodingTransform;

    constructor(attribute: PointAttribute?,
                transform: PredictionSchemeWrapDecodingTransform) {
        super(attribute);
        this.transform = transform;
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.PREDICTION_DIFFERENCE;
    }

    getTransformType(): i32 {
        return this.transform.getType();
    }

    areCorrectionsPositive(): bool {
        return this.transform.areCorrectionsPositive();
    }

    decodePredictionData(buffer: DecoderBuffer): bool {
        return this.transform.decodeTransformData(buffer);
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        this.transform.init(numComponents);
        // Decode the original value of the first element.
        let zeroVals = new Int32Array(numComponents);
        this.transform.computeOriginalValue(zeroVals, 0, inCorr, 0, outData, 0);

        // Decode the rest from the front using D(i) = D(i) + D(i - 1).
        for (let i = numComponents; i < size; i += numComponents) {
            this.transform.computeOriginalValue(
                outData, i - numComponents, inCorr, i, outData, i);
        }
        return true;
    }
}

export class PredictionSchemeDeltaDecoderNormalOcta extends PredictionSchemeDecoder {
    private transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform;

    constructor(attribute: PointAttribute?,
                transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform) {
        super(attribute);
        this.transform = transform;
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.PREDICTION_DIFFERENCE;
    }

    getTransformType(): i32 {
        return this.transform.getType();
    }

    areCorrectionsPositive(): bool {
        return this.transform.areCorrectionsPositive();
    }

    decodePredictionData(buffer: DecoderBuffer): bool {
        return this.transform.decodeTransformData(buffer);
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        this.transform.init(numComponents);
        let zeroVals = new Int32Array(numComponents);
        this.transform.computeOriginalValue(zeroVals, 0, inCorr, 0, outData, 0);

        for (let i = numComponents; i < size; i += numComponents) {
            this.transform.computeOriginalValue(
                outData, i - numComponents, inCorr, i, outData, i);
        }
        return true;
    }
}
