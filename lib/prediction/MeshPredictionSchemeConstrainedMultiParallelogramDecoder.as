// Ported from draco
// mesh_prediction_scheme_constrained_multi_parallelogram_decoder.h, the
// scheme encoders pick at speeds 0 and 1, monomorphized like the
// parallelogram decoder: int32_t data, wrap decoding transform, mesh data over
// either corner table. Bitstream >= 2.2 only, which carries no mode byte.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "../attributes/PointAttribute";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { RAnsBitDecoder } from "../entropy/RAnsBitDecoder";
import { kInvalidCornerIndex } from "../mesh/CornerTable";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { computeParallelogramPrediction } from "./MeshPredictionSchemeParallelogramDecoder";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";

const kMaxNumParallelograms: i32 = 4;

export class MeshPredictionSchemeConstrainedMultiParallelogramDecoder extends PredictionSchemeDecoder {
    private transform: PredictionSchemeWrapDecodingTransform;
    private meshData: MeshPredictionSchemeData;
    // Whether each processed edge is a crease that must not predict, one flag
    // list per count of parallelograms available at the vertex.
    private isCreaseEdge: StaticArray<Uint8Array> = [
        new Uint8Array(0), new Uint8Array(0), new Uint8Array(0), new Uint8Array(0),
    ];

    constructor(attribute: PointAttribute?,
                transform: PredictionSchemeWrapDecodingTransform,
                meshData: MeshPredictionSchemeData) {
        super(attribute);
        this.transform = transform;
        this.meshData = meshData;
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.MESH_PREDICTION_CONSTRAINED_MULTI_PARALLELOGRAM;
    }

    getTransformType(): i32 {
        return this.transform.getType();
    }

    areCorrectionsPositive(): bool {
        return this.transform.areCorrectionsPositive();
    }

    isInitialized(): bool {
        return this.meshData.isInitialized();
    }

    decodePredictionData(buffer: DecoderBuffer): bool {
        let numCorners = this.meshData.cornerTable().numCorners();
        for (let i = 0; i < kMaxNumParallelograms; i++) {
            let numFlags = buffer.decodeVarintUint32();
            if (buffer.err || numFlags > <u32>numCorners) {
                return false;
            }
            if (numFlags > 0) {
                let flags = new Uint8Array(<i32>numFlags);
                let decoder = new RAnsBitDecoder();
                if (!decoder.startDecoding(buffer)) {
                    return false;
                }
                for (let j = 0; j < <i32>numFlags; j++) {
                    unchecked(flags[j] = decoder.decodeNextBit() ? 1 : 0);
                }
                decoder.endDecoding();
                this.isCreaseEdge[i] = flags;
            }
        }
        return this.transform.decodeTransformData(buffer);
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        this.transform.init(numComponents);

        // Predicted values for every simple parallelogram found at a vertex.
        let predVals = new StaticArray<Int32Array>(kMaxNumParallelograms);
        for (let i = 0; i < kMaxNumParallelograms; i++) {
            predVals[i] = new Int32Array(numComponents);
        }
        this.transform.computeOriginalValue(predVals[0], 0, inCorr, 0, outData, 0);

        let table = this.meshData.cornerTable();
        let vertexToDataMap = this.meshData.vertexToDataMap();
        let isCreaseEdgePos = new Int32Array(kMaxNumParallelograms);
        let multiPredVals = new Int32Array(numComponents);

        let cornerMap = this.meshData.dataToCornerMap();
        let cornerMapSize = cornerMap.size();
        if (cornerMapSize * numComponents > size) {
            return false;
        }
        for (let p = 1; p < cornerMapSize; p++) {
            let startCornerId = cornerMap.get(p);
            let cornerId = startCornerId;
            let numParallelograms = 0;
            let firstPass = true;
            while (cornerId != kInvalidCornerIndex) {
                if (computeParallelogramPrediction(
                        p, cornerId, table, vertexToDataMap, outData, numComponents,
                        predVals[numParallelograms])) {
                    numParallelograms++;
                    if (numParallelograms == kMaxNumParallelograms) {
                        break;
                    }
                }
                // Swing left around the vertex, then right from the start
                // corner once a boundary stops the left swing.
                cornerId = firstPass ? table.swingLeft(cornerId) : table.swingRight(cornerId);
                if (cornerId == startCornerId) {
                    break;
                }
                if (cornerId == kInvalidCornerIndex && firstPass) {
                    firstPass = false;
                    cornerId = table.swingRight(startCornerId);
                }
            }

            // Average the parallelograms the encoder did not flag as creases.
            let numUsedParallelograms = 0;
            if (numParallelograms > 0) {
                multiPredVals.fill(0);
                let context = numParallelograms - 1;
                let flags = this.isCreaseEdge[context];
                for (let i = 0; i < numParallelograms; i++) {
                    let pos = isCreaseEdgePos[context];
                    isCreaseEdgePos[context] = pos + 1;
                    if (pos >= flags.length) {
                        return false;
                    }
                    if (unchecked(flags[pos]) == 0) {
                        numUsedParallelograms++;
                        let pred = predVals[i];
                        for (let j = 0; j < numComponents; j++) {
                            // i32 addition wraps like the C++ AddAsUnsigned.
                            unchecked(multiPredVals[j] += pred[j]);
                        }
                    }
                }
            }
            let dstOffset = p * numComponents;
            if (numUsedParallelograms == 0) {
                // No usable parallelogram: predict from the last decoded value.
                let srcOffset = (p - 1) * numComponents;
                this.transform.computeOriginalValue(
                    outData, srcOffset, inCorr, dstOffset, outData, dstOffset);
            } else {
                for (let c = 0; c < numComponents; c++) {
                    unchecked(multiPredVals[c] /= numUsedParallelograms);
                }
                this.transform.computeOriginalValue(
                    multiPredVals, 0, inCorr, dstOffset, outData, dstOffset);
            }
        }
        return true;
    }
}
