// Ported from draco attributes/attribute_transform.h/.cc (decoder subset).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "./PointAttribute";
import { AttributeTransformData } from "./AttributeTransformData";

export abstract class AttributeTransform {
    copyToAttributeTransformData(outData: AttributeTransformData): void {}

    transferToAttribute(attribute: PointAttribute): bool {
        let transformData = new AttributeTransformData();
        this.copyToAttributeTransformData(transformData);
        attribute.setAttributeTransformData(transformData);
        return true;
    }

    inverseTransformAttribute(
        attribute: PointAttribute, targetAttribute: PointAttribute): bool {
        return false;
    }

    decodeParameters(
        attribute: PointAttribute, decoderBuffer: DecoderBuffer): bool {
        return false;
    }
}
