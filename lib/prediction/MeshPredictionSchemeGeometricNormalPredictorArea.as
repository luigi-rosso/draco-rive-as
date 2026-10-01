// Ported from draco mesh_prediction_scheme_geometric_normal_predictor_base.h +
// mesh_prediction_scheme_geometric_normal_predictor_area.h, monomorphized for
// int32_t data. Only TRIANGLE_AREA mode is ported: ONE_TRIANGLE can only be
// selected by pre-2.2 bitstreams.
//
// Estimates the normal from the triangles around the corner, weighted by area.

import { PointAttribute } from "../attributes/PointAttribute";
import { VertexCornersIterator } from "../mesh/CornerTable";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";

export class MeshPredictionSchemeGeometricNormalPredictorArea {
    private posAttribute: PointAttribute? = null;
    private entryToPointIdMap: Int32Array = new Int32Array(0);
    private meshData: MeshPredictionSchemeData;
    // Scratch for position reads.
    private posVal: Float64Array = new Float64Array(3);

    constructor(meshData: MeshPredictionSchemeData) {
        this.meshData = meshData;
    }

    setPositionAttribute(positionAttribute: PointAttribute): void {
        this.posAttribute = positionAttribute;
    }

    setEntryToPointIdMap(map: Int32Array): void {
        this.entryToPointIdMap = map;
    }

    isInitialized(): bool {
        if (this.posAttribute == null) {
            return false;
        }
        if (this.entryToPointIdMap.length == 0) {
            return false;
        }
        return true;
    }

    // Loads the position for |dataId| into posVal (quantized integers, exact
    // in f64; matches C++ ConvertValue to int64).
    private loadPositionForDataId(dataId: i32): void {
        let pointId = this.entryToPointIdMap[dataId];
        let att = this.posAttribute!;
        att.convertValue(<i32>att.mappedIndex(pointId), this.posVal);
    }

    private loadPositionForCorner(ci: i32): void {
        let table = this.meshData.cornerTable();
        let vertId = table.vertex(ci);
        let dataId = this.meshData.vertexToDataMap()[vertId];
        this.loadPositionForDataId(dataId);
    }

    // Computes the predicted normal (not yet octahedral) for |cornerId| into
    // prediction[0..2].
    computePredictedValue(cornerId: i32, prediction: Int32Array): void {
        let table = this.meshData.cornerTable();
        // The predicted normal comes from the surrounding triangles of the
        // given corner table connectivity.
        let cit = new VertexCornersIterator(table, cornerId);
        // The central vertex position does not change in the loop.
        this.loadPositionForCorner(cornerId);
        let centX = <i64>this.posVal[0];
        let centY = <i64>this.posVal[1];
        let centZ = <i64>this.posVal[2];

        let normalX: i64 = 0;
        let normalY: i64 = 0;
        let normalZ: i64 = 0;
        while (!cit.end()) {
            // TRIANGLE_AREA mode: corners of the currently iterated triangle.
            let cNext = table.next(cit.corner());
            let cPrev = table.previous(cit.corner());
            this.loadPositionForCorner(cNext);
            let dNextX = <i64>this.posVal[0] - centX;
            let dNextY = <i64>this.posVal[1] - centY;
            let dNextZ = <i64>this.posVal[2] - centZ;
            this.loadPositionForCorner(cPrev);
            let dPrevX = <i64>this.posVal[0] - centX;
            let dPrevY = <i64>this.posVal[1] - centY;
            let dPrevZ = <i64>this.posVal[2] - centZ;

            // Cross product; i64 addition wraps like the C++ unsigned math.
            normalX += dNextY * dPrevZ - dNextZ * dPrevY;
            normalY += dNextZ * dPrevX - dNextX * dPrevZ;
            normalZ += dNextX * dPrevY - dNextY * dPrevX;

            cit.next();
        }

        // Convert to i32 range keeping entries below the upper bound.
        let upperBound: i64 = 1 << 29;
        let absSum = (normalX < 0 ? -normalX : normalX) +
            (normalY < 0 ? -normalY : normalY) +
            (normalZ < 0 ? -normalZ : normalZ);
        if (absSum > upperBound) {
            let quotient = absSum / upperBound;
            normalX /= quotient;
            normalY /= quotient;
            normalZ /= quotient;
        }
        prediction[0] = <i32>normalX;
        prediction[1] = <i32>normalY;
        prediction[2] = <i32>normalZ;
    }
}
