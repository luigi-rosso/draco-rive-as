// Ported from draco attributes/attribute_octahedron_transform.h/.cc
// (decoder subset). Expands octahedral int32 coords (2 per point) to float32
// unit normals (3 per point) via the shared OctahedronToolBox.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType } from "../core/DracoTypes";
import { AttributeTransform } from "./AttributeTransform";
import { AttributeTransformData } from "./AttributeTransformData";
import { AttributeTransformType } from "./AttributeTransformType";
import { OctahedronToolBox } from "./NormalCompressionUtils";
import { PointAttribute } from "./PointAttribute";

export class AttributeOctahedronTransform extends AttributeTransform {
    private _quantizationBits: i32 = -1;
    private _tmpVec: Float32Array = new Float32Array(3);

    copyToAttributeTransformData(outData: AttributeTransformData): void {
        outData.transformType = AttributeTransformType.OCTAHEDRON_TRANSFORM;
        outData.appendInt32(this._quantizationBits);
    }

    decodeParameters(
        attribute: PointAttribute, decoderBuffer: DecoderBuffer): bool {
        let qBits = <i32>decoderBuffer.decodeUint8();
        if (decoderBuffer.err) {
            return false;
        }
        this._quantizationBits = qBits;
        return true;
    }

    inverseTransformAttribute(
        attribute: PointAttribute, targetAttribute: PointAttribute): bool {
        if (targetAttribute.dataType != DataType.FLOAT32) {
            return false;
        }
        if (targetAttribute.numComponents != 3) {
            return false;
        }

        let toolBox = new OctahedronToolBox();
        if (!toolBox.setQuantizationBits(this._quantizationBits)) {
            return false;
        }

        let numPoints = targetAttribute.size();
        let srcAddr = attribute.getAddress(0);
        let src = Int32Array.wrap(srcAddr.buffer, srcAddr.byteOffset, numPoints * 2);
        let dstAddr = targetAttribute.getAddress(0);
        let dst = Float32Array.wrap(dstAddr.buffer, dstAddr.byteOffset, numPoints * 3);

        let outVec = this._tmpVec;
        for (let i = 0; i < numPoints; i++) {
            toolBox.quantizedOctahedralCoordsToUnitVector(
                unchecked(src[i * 2]), unchecked(src[i * 2 + 1]), outVec);
            unchecked(dst[i * 3] = unchecked(outVec[0]));
            unchecked(dst[i * 3 + 1] = unchecked(outVec[1]));
            unchecked(dst[i * 3 + 2] = unchecked(outVec[2]));
        }
        return true;
    }
}
