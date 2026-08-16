// Ported from draco mesh_prediction_scheme_tex_coords_portable_predictor.h,
// monomorphized for int32_t data (decoder path only; the is_encoder_t = true
// template branch is dropped). VectorD math is unrolled into scalar i64 locals.

import { PointAttribute } from "../attributes/PointAttribute";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";

export const kTexCoordsNumComponents: i32 = 2;

// C++ core/math_utils.h IntSqrt: deterministic floor(sqrt(x)) for uint64.
export function intSqrt(number: u64): u64 {
    if (number == 0) {
        return 0;
    }
    // Initial estimate of the square root as log2(number).
    let actNumber = number;
    let squareRoot: u64 = 1;
    while (actNumber >= 2) {
        // Double until |squareRoot * squareRoot > number|.
        squareRoot *= 2;
        actNumber /= 4;
    }
    // Newton's (Babylonian) method for the true floor(sqrt()).
    do {
        squareRoot = (squareRoot + number / squareRoot) / 2;
        // After the first iteration the estimate is always >= the true root,
        // so convergence is the square dropping to or below the input.
    } while (squareRoot * squareRoot > number);
    return squareRoot;
}

function absMax2(a: i64, b: i64): i64 {
    let aa = a < 0 ? -a : a;
    let ab = b < 0 ? -b : b;
    return aa > ab ? aa : ab;
}

export class MeshPredictionSchemeTexCoordsPortablePredictor {
    private posAttribute: PointAttribute | null = null;
    private entryToPointIdMap: Int32Array = new Int32Array(0);
    private _predictedValue: Int32Array = new Int32Array(kTexCoordsNumComponents);
    // Decoded UV flips, consumed from the back.
    private orientations: Uint8Array = new Uint8Array(0);
    private numOrientations: i32 = 0;
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
        return this.posAttribute != null;
    }

    predictedValue(): Int32Array {
        return this._predictedValue;
    }

    orientation(i: i32): bool {
        return this.orientations[i] != 0;
    }

    setOrientation(i: i32, v: bool): void {
        this.orientations[i] = v ? 1 : 0;
    }

    resizeOrientations(numOrientations: i32): void {
        this.orientations = new Uint8Array(numOrientations);
        this.numOrientations = numOrientations;
    }

    // Reads the position for |entryId| into posVal; components are quantized
    // integers, exactly representable in f64 (matches C++ ConvertValue to
    // int64).
    private loadPosition(entryId: i32): void {
        let pointId = this.entryToPointIdMap[entryId];
        let att = this.posAttribute!;
        att.convertValue(<i32>att.mappedIndex(pointId), this.posVal);
    }

    // Computes the predicted UV coordinates for |cornerId| into
    // predictedValue(). Decoder-only port of ComputePredictedValue<false>.
    computePredictedValue(cornerId: i32, data: Int32Array, dataId: i32): bool {
        // The prediction uses the positions on all corners of the processed
        // triangle; the UVs on the next/previous corners must be already
        // decoded for the best prediction.
        let table = this.meshData.cornerTable();
        let nextCornerId = table.next(cornerId);
        let prevCornerId = table.previous(cornerId);
        // Encoded data ids (the decoding order of the UV coordinates) from
        // the next and previous corners.
        let vertexToData = this.meshData.vertexToDataMap();
        let nextDataId = vertexToData[table.vertex(nextCornerId)];
        let prevDataId = vertexToData[table.vertex(prevCornerId)];

        if (prevDataId < dataId && nextDataId < dataId) {
            // Both other corners have available UV coordinates.
            let nUvX = <i64>data[nextDataId * kTexCoordsNumComponents];
            let nUvY = <i64>data[nextDataId * kTexCoordsNumComponents + 1];
            let pUvX = <i64>data[prevDataId * kTexCoordsNumComponents];
            let pUvY = <i64>data[prevDataId * kTexCoordsNumComponents + 1];
            if (pUvX == nUvX && pUvY == nUvY) {
                // No reliable prediction on degenerated UV triangles.
                this._predictedValue[0] = <i32>pUvX;
                this._predictedValue[1] = <i32>pUvY;
                return true;
            }

            // Positions at all corners.
            this.loadPosition(dataId);
            let tipX = <i64>this.posVal[0];
            let tipY = <i64>this.posVal[1];
            let tipZ = <i64>this.posVal[2];
            this.loadPosition(nextDataId);
            let nextX = <i64>this.posVal[0];
            let nextY = <i64>this.posVal[1];
            let nextZ = <i64>this.posVal[2];
            this.loadPosition(prevDataId);
            let prevX = <i64>this.posVal[0];
            let prevY = <i64>this.posVal[1];
            let prevZ = <i64>this.posVal[2];

            // The triangle above the UV triangle predicts the coordinate on
            // the tip corner C: X is the projection of C onto PN.
            //
            //              C
            //             /.  \
            //            / .     \
            //           /  .        \
            //          N---X----------P
            let pnX = prevX - nextX;
            let pnY = prevY - nextY;
            let pnZ = prevZ - nextZ;
            let pnNorm2Squared = <u64>(pnX * pnX + pnY * pnY + pnZ * pnZ);
            if (pnNorm2Squared != 0) {
                // |s = PN.Dot(CN) / PN.SquaredNorm2()| maps X into UV space as
                // |X_UV = N_UV + s * PN_UV|; all integer math runs in the
                // non-normalized space scaled by pnNorm2Squared.
                let cnX = tipX - nextX;
                let cnY = tipY - nextY;
                let cnZ = tipZ - nextZ;
                let cnDotPn = pnX * cnX + pnY * cnY + pnZ * cnZ;

                let pnUvX = pUvX - nUvX;
                let pnUvY = pUvY - nUvY;

                let nUvAbsMaxElement = absMax2(nUvX, nUvY);
                if (<u64>nUvAbsMaxElement > <u64>i64.MAX_VALUE / pnNorm2Squared) {
                    // The multiplication below would overflow.
                    return false;
                }
                let pnUvAbsMaxElement = absMax2(pnUvX, pnUvY);
                let absCnDotPn = cnDotPn < 0 ? -cnDotPn : cnDotPn;
                if (absCnDotPn > i64.MAX_VALUE / pnUvAbsMaxElement) {
                    // The squared length calculation would overflow.
                    return false;
                }
                let xUvX = nUvX * <i64>pnNorm2Squared + cnDotPn * pnUvX;
                let xUvY = nUvY * <i64>pnNorm2Squared + cnDotPn * pnUvY;

                let pnAbsMaxElement = absMax2(absMax2(pnX, pnY), pnZ);
                if (absCnDotPn > i64.MAX_VALUE / pnAbsMaxElement) {
                    // The squared length calculation would overflow.
                    return false;
                }

                // Squared length of CX in the position coordinate system.
                let xPosX = nextX + (cnDotPn * pnX) / <i64>pnNorm2Squared;
                let xPosY = nextY + (cnDotPn * pnY) / <i64>pnNorm2Squared;
                let xPosZ = nextZ + (cnDotPn * pnZ) / <i64>pnNorm2Squared;
                let cxX = tipX - xPosX;
                let cxY = tipY - xPosY;
                let cxZ = tipZ - xPosZ;
                let cxNorm2Squared = <u64>(cxX * cxX + cxY * cxY + cxZ * cxZ);

                // CX_UV is PN_UV rotated by 90 degrees, scaled by
                // CX.Norm2() / PN.Norm2(); in the scaled space
                // cx_uv = CX.Norm2() * PN.Norm2() * Rot(PN_UV).
                let cxUvX = pnUvY;
                let cxUvY = -pnUvX;
                let normSquared = intSqrt(cxNorm2Squared * pnNorm2Squared);
                cxUvX = cxUvX * <i64>normSquared;
                cxUvY = cxUvY * <i64>normSquared;

                // The decoded orientation selects whether CX_UV is added to
                // or subtracted from X_UV.
                if (this.numOrientations == 0) {
                    return false;
                }
                this.numOrientations--;
                let orientation = this.orientations[this.numOrientations] != 0;

                // Operations run in unsigned to avoid signed overflow; the
                // result matches for non-overflowing values.
                let predictedUvX: i64;
                let predictedUvY: i64;
                if (orientation) {
                    predictedUvX = <i64>(<u64>xUvX + <u64>cxUvX) / <i64>pnNorm2Squared;
                    predictedUvY = <i64>(<u64>xUvY + <u64>cxUvY) / <i64>pnNorm2Squared;
                } else {
                    predictedUvX = <i64>(<u64>xUvX - <u64>cxUvX) / <i64>pnNorm2Squared;
                    predictedUvY = <i64>(<u64>xUvY - <u64>cxUvY) / <i64>pnNorm2Squared;
                }
                this._predictedValue[0] = <i32>predictedUvX;
                this._predictedValue[1] = <i32>predictedUvY;
                return true;
            }
        }
        // No textures on both corners or invalid position data; fall back to
        // delta coding.
        let dataOffset = 0;
        if (prevDataId < dataId) {
            // Use the value on the previous corner as the prediction.
            dataOffset = prevDataId * kTexCoordsNumComponents;
        }
        if (nextDataId < dataId) {
            // Use the value on the next corner as the prediction.
            dataOffset = nextDataId * kTexCoordsNumComponents;
        } else {
            // No other corner has a valid value; use the last decoded value.
            if (dataId > 0) {
                dataOffset = (dataId - 1) * kTexCoordsNumComponents;
            } else {
                // The first value is predicted as 0.
                for (let i = 0; i < kTexCoordsNumComponents; i++) {
                    this._predictedValue[i] = 0;
                }
                return true;
            }
        }
        for (let i = 0; i < kTexCoordsNumComponents; i++) {
            this._predictedValue[i] = data[dataOffset + i];
        }
        return true;
    }
}
