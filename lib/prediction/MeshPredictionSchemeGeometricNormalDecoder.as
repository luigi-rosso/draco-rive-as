// Ported from draco mesh_prediction_scheme_geometric_normal_decoder.h,
// monomorphized for int32_t data + the canonicalized octahedron decoding
// transform (bitstream >= 2.2: no legacy prediction-mode byte).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { RAnsBitDecoder } from "../entropy/RAnsBitDecoder";
import { PointAttribute } from "../attributes/PointAttribute";
import { GeometryAttributeType } from "../attributes/GeometryAttribute";
import { OctahedronToolBox } from "../attributes/NormalCompressionUtils";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "./PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";
import { MeshPredictionSchemeGeometricNormalPredictorArea } from "./MeshPredictionSchemeGeometricNormalPredictorArea";

export class MeshPredictionSchemeGeometricNormalDecoder extends PredictionSchemeDecoder {
    private transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform;
    private meshData: MeshPredictionSchemeData;
    private predictor: MeshPredictionSchemeGeometricNormalPredictorArea;
    private octahedronToolBox: OctahedronToolBox = new OctahedronToolBox();
    private flipNormalBitDecoder: RAnsBitDecoder = new RAnsBitDecoder();

    constructor(attribute: PointAttribute | null,
                transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform,
                meshData: MeshPredictionSchemeData) {
        super(attribute);
        this.transform = transform;
        this.meshData = meshData;
        this.predictor = new MeshPredictionSchemeGeometricNormalPredictorArea(meshData);
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.MESH_PREDICTION_GEOMETRIC_NORMAL;
    }

    getTransformType(): i32 {
        return this.transform.getType();
    }

    areCorrectionsPositive(): bool {
        return this.transform.areCorrectionsPositive();
    }

    isInitialized(): bool {
        if (!this.predictor.isInitialized()) {
            return false;
        }
        if (!this.meshData.isInitialized()) {
            return false;
        }
        if (!this.octahedronToolBox.isInitialized()) {
            return false;
        }
        return true;
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

    setQuantizationBits(q: i32): void {
        this.octahedronToolBox.setQuantizationBits(q);
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        this.setQuantizationBits(this.transform.quantizationBits());
        this.predictor.setEntryToPointIdMap(entryToPointIdMap);

        // inCorr is expected in octahedral coordinates (portable attribute,
        // two components).
        let cornerMap = this.meshData.dataToCornerMap();
        let cornerMapSize = cornerMap.size();

        let predNormal3D = new Int32Array(3);
        let predNormalOct = new Int32Array(2);

        for (let dataId = 0; dataId < cornerMapSize; dataId++) {
            let cornerId = cornerMap.get(dataId);
            this.predictor.computePredictedValue(cornerId, predNormal3D);

            // Compute predicted octahedral coordinates.
            this.octahedronToolBox.canonicalizeIntegerVector(predNormal3D);
            if (this.flipNormalBitDecoder.decodeNextBit()) {
                predNormal3D[0] = -predNormal3D[0];
                predNormal3D[1] = -predNormal3D[1];
                predNormal3D[2] = -predNormal3D[2];
            }
            this.octahedronToolBox.integerVectorToQuantizedOctahedralCoords(
                predNormal3D, predNormalOct);

            let dataOffset = dataId * 2;
            this.transform.computeOriginalValue(
                predNormalOct, 0, inCorr, dataOffset, outData, dataOffset);
        }
        this.flipNormalBitDecoder.endDecoding();
        return true;
    }

    decodePredictionData(buffer: DecoderBuffer): bool {
        // Data needed by the transform.
        if (!this.transform.decodeTransformData(buffer)) {
            return false;
        }
        // Init normal flips.
        return this.flipNormalBitDecoder.startDecoding(buffer);
    }
}
