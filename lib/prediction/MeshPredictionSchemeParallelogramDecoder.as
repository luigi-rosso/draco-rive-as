// Ported from draco mesh_prediction_scheme_parallelogram_decoder.h +
// mesh_prediction_scheme_parallelogram_shared.h, monomorphized for the C++
// instantiation the subset uses: int32_t data, wrap decoding transform,
// mesh data over either corner table (CornerTableBase).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "../attributes/PointAttribute";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { CornerTableBase, kInvalidCornerIndex } from "../mesh/CornerTable";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";

// Computes the parallelogram prediction for a given corner and data entry id
// into |outPrediction|. Returns false when the prediction cannot be computed,
// e.g. because not all entry points are available yet
// (C++ ComputeParallelogramPrediction).
@inline
export unsafe function computeParallelogramPrediction(
    dataEntryId: i32, ci: i32, table: CornerTableBase,
    vertexToDataMap: Int32Array, inData: Int32Array, numComponents: i32,
    outPrediction: Int32Array): bool {
    let oci = table.opposite(ci);
    if (oci == kInvalidCornerIndex) {
        return false;
    }
    // One vertex of |table| corresponds to exactly one attribute value entry
    // (C++ GetParallelogramEntries).
    let vertOpp = unchecked(vertexToDataMap[table.vertex(oci)]);
    let vertNext = unchecked(vertexToDataMap[table.vertex(table.next(oci))]);
    let vertPrev = unchecked(vertexToDataMap[table.vertex(table.previous(oci))]);
    if (vertOpp < dataEntryId && vertNext < dataEntryId && vertPrev < dataEntryId) {
        // Apply the parallelogram prediction.
        let vOppOff = vertOpp * numComponents;
        let vNextOff = vertNext * numComponents;
        let vPrevOff = vertPrev * numComponents;
        let inPtr = inData.dataStart;
        let outPtr = outPrediction.dataStart;
        for (let c = 0; c < numComponents; c++) {
            let result = load<i32>(inPtr + (<usize>(vNextOff + c) << 2)) +
                load<i32>(inPtr + (<usize>(vPrevOff + c) << 2)) -
                load<i32>(inPtr + (<usize>(vOppOff + c) << 2));
            store<i32>(outPtr + (<usize>c << 2), result);
        }
        return true;
    }
    return false; // Not all data is available for prediction.
}

export class MeshPredictionSchemeParallelogramDecoder extends PredictionSchemeDecoder {
    private transform: PredictionSchemeWrapDecodingTransform;
    private meshData: MeshPredictionSchemeData;

    constructor(attribute: PointAttribute?,
                transform: PredictionSchemeWrapDecodingTransform,
                meshData: MeshPredictionSchemeData) {
        super(attribute);
        this.transform = transform;
        this.meshData = meshData;
    }

    getPredictionMethod(): i32 {
        return PredictionSchemeMethod.MESH_PREDICTION_PARALLELOGRAM;
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
        return this.transform.decodeTransformData(buffer);
    }

    computeOriginalValues(
        inCorr: Int32Array, outData: Int32Array, size: i32, numComponents: i32,
        entryToPointIdMap: Int32Array): bool {
        this.transform.init(numComponents);

        let table = this.meshData.cornerTable();
        let vertexToDataMap = this.meshData.vertexToDataMap();

        // Prediction values, initialized to zero.
        let predVals = new Int32Array(numComponents);

        // Restore the first value.
        this.transform.computeOriginalValue(predVals, 0, inCorr, 0, outData, 0);

        let cornerMap = this.meshData.dataToCornerMap();
        let cornerMapSize = cornerMap.size();
        for (let p = 1; p < cornerMapSize; p++) {
            let cornerId = cornerMap.get(p);
            let dstOffset = p * numComponents;
            if (!computeParallelogramPrediction(
                    p, cornerId, table, vertexToDataMap, outData, numComponents,
                    predVals)) {
                // The parallelogram could not be computed (some vertices are
                // not decoded yet); use the last decoded point as a reference
                // (delta coding).
                let srcOffset = (p - 1) * numComponents;
                this.transform.computeOriginalValue(
                    outData, srcOffset, inCorr, dstOffset, outData, dstOffset);
            } else {
                // Apply the parallelogram prediction.
                this.transform.computeOriginalValue(
                    predVals, 0, inCorr, dstOffset, outData, dstOffset);
            }
        }
        return true;
    }
}
