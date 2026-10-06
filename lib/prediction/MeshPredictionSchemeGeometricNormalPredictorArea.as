// Ported from draco mesh_prediction_scheme_geometric_normal_predictor_base.h +
// mesh_prediction_scheme_geometric_normal_predictor_area.h, monomorphized for
// int32_t data. Only TRIANGLE_AREA mode is ported: ONE_TRIANGLE can only be
// selected by pre-2.2 bitstreams.
//
// Estimates the normal from the triangles around the corner, weighted by area.

import { PointAttribute } from "../attributes/PointAttribute";
import { VertexCornersIterator } from "../mesh/CornerTable";
import { MeshPredictionPositionReader } from "./MeshPredictionPositionReader";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";

export class MeshPredictionSchemeGeometricNormalPredictorArea {
    private pos: MeshPredictionPositionReader = new MeshPredictionPositionReader();
    private meshData: MeshPredictionSchemeData;
    private cit: VertexCornersIterator? = null;

    constructor(meshData: MeshPredictionSchemeData) {
        this.meshData = meshData;
    }

    setPositionAttribute(positionAttribute: PointAttribute): void {
        this.pos.attribute = positionAttribute;
    }

    setEntryToPointIdMap(map: Int32Array): void {
        this.pos.entryToPointIdMap = map;
    }

    isInitialized(): bool {
        if (this.pos.attribute == null) {
            return false;
        }
        if (this.pos.entryToPointIdMap.length == 0) {
            return false;
        }
        return true;
    }

    private loadPositionForCorner(ci: i32): void {
        let vertId = this.meshData.cornerTable().vertex(ci);
        this.pos.load(this.meshData.vertexToDataMap()[vertId]);
    }

    // Computes the predicted normal (not yet octahedral) for |cornerId| into
    // prediction[0..2].
    computePredictedValue(cornerId: i32, prediction: Int32Array): void {
        let table = this.meshData.cornerTable();
        let pos = this.pos;
        // The predicted normal comes from the surrounding triangles of the
        // given corner table connectivity.
        let cit = this.cit;
        if (cit == null) {
            cit = new VertexCornersIterator(table, cornerId);
            this.cit = cit;
        } else {
            cit.resetFromCorner(table, cornerId);
        }
        // The central vertex position does not change in the loop.
        this.loadPositionForCorner(cornerId);
        let centX = pos.x;
        let centY = pos.y;
        let centZ = pos.z;

        let normalX: i64 = 0;
        let normalY: i64 = 0;
        let normalZ: i64 = 0;
        while (!cit.end()) {
            // TRIANGLE_AREA mode: corners of the currently iterated triangle.
            let cNext = table.next(cit.corner());
            let cPrev = table.previous(cit.corner());
            this.loadPositionForCorner(cNext);
            let dNextX = pos.x - centX;
            let dNextY = pos.y - centY;
            let dNextZ = pos.z - centZ;
            this.loadPositionForCorner(cPrev);
            let dPrevX = pos.x - centX;
            let dPrevY = pos.y - centY;
            let dPrevZ = pos.z - centZ;

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
