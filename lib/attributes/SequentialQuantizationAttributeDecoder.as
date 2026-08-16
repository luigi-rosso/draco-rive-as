// Ported from draco
// compression/attributes/sequential_quantization_attribute_decoder.h/.cc
// (bitstream >= 2.2 subset). Decodes integers, then dequantizes to float32.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType } from "../core/DracoTypes";
import { AttributeQuantizationTransform } from "./AttributeQuantizationTransform";
import { SequentialIntegerAttributeDecoder } from "./SequentialIntegerAttributeDecoder";
import { PointAttribute } from "./PointAttribute";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

export class SequentialQuantizationAttributeDecoder extends SequentialIntegerAttributeDecoder {
    private quantizationTransform_: AttributeQuantizationTransform =
        new AttributeQuantizationTransform();

    init(decoder: PointCloudDecoder, attributeId: i32): bool {
        if (!super.init(decoder, attributeId)) {
            return false;
        }
        // Only floating point attributes can be quantized.
        if (this.attribute().dataType != DataType.FLOAT32) {
            return false;
        }
        return true;
    }

    decodeDataNeededByPortableTransform(
        pointIds: Int32Array, buffer: DecoderBuffer): bool {
        if (!this.decodeQuantizedDataInfo()) {
            return false;
        }
        return this.quantizationTransform_.transferToAttribute(this.portableAttribute()!);
    }

    // Dequantize instead of the generic integer store.
    protected storeValues(numValues: i32): bool {
        return this.dequantizeValues(numValues);
    }

    private decodeQuantizedDataInfo(): bool {
        let att = this.getPortableAttribute();
        if (att == null) {
            // Backward-compatibility path only; the transform just needs the
            // component count, identical on both attributes.
            att = this.attribute();
        }
        return this.quantizationTransform_.decodeParameters(att, this.decoder().buffer());
    }

    private dequantizeValues(numValues: i32): bool {
        let portable = this.getPortableAttribute();
        if (portable == null) {
            return false;
        }
        return this.quantizationTransform_.inverseTransformAttribute(
            portable, this.attribute());
    }
}
