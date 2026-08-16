// Ported from draco attributes/attribute_quantization_transform.h/.cc
// (decoder subset). Dequantizes int32 portable values to float32; all
// arithmetic stays in f32 to match C++ bit for bit.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType } from "../core/DracoTypes";
import { Dequantizer } from "../core/QuantizationUtils";
import { AttributeTransform } from "./AttributeTransform";
import { AttributeTransformData } from "./AttributeTransformData";
import { AttributeTransformType } from "./AttributeTransformType";
import { PointAttribute } from "./PointAttribute";

export function isQuantizationValid(quantizationBits: i32): bool {
    return quantizationBits >= 1 && quantizationBits <= 30;
}

export class AttributeQuantizationTransform extends AttributeTransform {
    private _quantizationBits: i32 = -1;
    private _minValues: Float32Array = new Float32Array(0);
    private _range: f32 = 0;

    copyToAttributeTransformData(outData: AttributeTransformData): void {
        outData.transformType = AttributeTransformType.QUANTIZATION_TRANSFORM;
        outData.appendInt32(this._quantizationBits);
        for (let i = 0; i < this._minValues.length; i++) {
            outData.appendFloat32(this._minValues[i]);
        }
        outData.appendFloat32(this._range);
    }

    decodeParameters(
        attribute: PointAttribute, decoderBuffer: DecoderBuffer): bool {
        let numComponents = attribute.numComponents;
        this._minValues = new Float32Array(numComponents);
        for (let i = 0; i < numComponents; i++) {
            this._minValues[i] = decoderBuffer.decodeFloat32();
            if (decoderBuffer.err) {
                return false;
            }
        }
        this._range = decoderBuffer.decodeFloat32();
        if (decoderBuffer.err) {
            return false;
        }
        let qBits = <i32>decoderBuffer.decodeUint8();
        if (decoderBuffer.err) {
            return false;
        }
        if (!isQuantizationValid(qBits)) {
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

        let maxQuantizedValue = (1 << this._quantizationBits) - 1;
        let numComponents = targetAttribute.numComponents;
        let dequantizer = new Dequantizer();
        if (!dequantizer.initFromRange(this._range, maxQuantizedValue)) {
            return false;
        }

        let numValues = targetAttribute.size();
        let total = numValues * numComponents;
        let delta = dequantizer.delta;
        let minValues = this._minValues;

        // Source holds int32, target float32; both buffers start at offset 0.
        let srcAddr = attribute.getAddress(0);
        let src = Int32Array.wrap(srcAddr.buffer, srcAddr.byteOffset, total);
        let dstAddr = targetAttribute.getAddress(0);
        let dst = Float32Array.wrap(dstAddr.buffer, dstAddr.byteOffset, total);

        let o = 0;
        for (let i = 0; i < numValues; i++) {
            for (let c = 0; c < numComponents; c++) {
                unchecked(dst[o] = <f32>src[o] * delta + unchecked(minValues[c]));
                o++;
            }
        }
        return true;
    }

    quantizationBits(): i32 {
        return this._quantizationBits;
    }

    range(): f32 {
        return this._range;
    }

    minValue(axis: i32): f32 {
        return this._minValues[axis];
    }
}
