// Ported from draco mesh_prediction_scheme_tex_coords_portable_decoder.h,
// monomorphized for int32_t data + wrap decoding transform.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { RAnsBitDecoder } from "../entropy/RAnsBitDecoder";
import { PointAttribute } from "../attributes/PointAttribute";
import { GeometryAttributeType } from "../attributes/GeometryAttribute";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";
import {
    MeshPredictionSchemeTexCoordsPortablePredictor,
    kTexCoordsNumComponents,
} from "./MeshPredictionSchemeTexCoordsPortablePredictor";

export class MeshPredictionSchemeTexCoordsPortableDecoder extends PredictionSchemeDecoder {
    private transform: PredictionSchemeWrapDecodingTransform;
    private meshData: MeshPredictionSchemeData;
    private predictor: MeshPredictionSchemeTexCoordsPortablePredictor;

    constructor(attribute: PointAttribute?,
                transform: PredictionSchemeWrapDecodingTransform,
                meshData: MeshPredictionSchemeData) {
        super(attribute);
        this.transform = transform;
        this.meshData = meshData;
        this.predictor = new MeshPredictionSchemeTexCoordsPortablePredictor(meshData);
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.MESH_PREDICTION_TEX_COORDS_PORTABLE;
    }

    getTransformType(): i32 {
        return this.transform.getType();
    }

    areCorrectionsPositive(): bool {
        return this.transform.areCorrectionsPositive();
    }

    isInitialized(): bool {
        return this.predictor.isInitialized() && this.meshData.isInitialized();
    }

    getNumParentAttributes(): i32 {
        return 1;
    }

    getParentAttributeType(i: i32): i32 {
        return GeometryAttributeType.POSITION;
    }

    setParentAttribute(att: PointAttribute): bool {
        if (att.attributeType != GeometryAttributeType.POSITION) {
            return false; // Invalid attribute type.
        }
        if (att.numComponents != 3) {
            return false; // Only 3 component positions are supported.
        }
        this.predictor.setPositionAttribute(att);
        return true;
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        if (numComponents != kTexCoordsNumComponents) {
            return false;
        }
        this.predictor.setEntryToPointIdMap(entryToPointIdMap);
        this.transform.init(numComponents);

        let cornerMap = this.meshData.dataToCornerMap();
        let cornerMapSize = cornerMap.size();
        for (let p = 0; p < cornerMapSize; p++) {
            let cornerId = cornerMap.get(p);
            if (!this.predictor.computePredictedValue(cornerId, outData, p)) {
                return false;
            }

            let dstOffset = p * numComponents;
            this.transform.computeOriginalValue(
                this.predictor.predictedValue(), 0, inCorr, dstOffset, outData,
                dstOffset);
        }
        return true;
    }

    decodePredictionData(buffer: DecoderBuffer): bool {
        // Decode the delta-coded orientations.
        let numOrientations = buffer.decodeInt32();
        if (buffer.err || numOrientations < 0) {
            return false;
        }
        this.predictor.resizeOrientations(numOrientations);
        let lastOrientation = true;
        let decoder = new RAnsBitDecoder();
        if (!decoder.startDecoding(buffer)) {
            return false;
        }
        for (let i = 0; i < numOrientations; i++) {
            if (!decoder.decodeNextBit()) {
                lastOrientation = !lastOrientation;
            }
            this.predictor.setOrientation(i, lastOrientation);
        }
        decoder.endDecoding();
        return this.transform.decodeTransformData(buffer);
    }
}
