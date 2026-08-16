// Ported from draco
// compression/attributes/sequential_attribute_decoders_controller.h/.cc.
// One SequentialAttributeDecoder per attribute (type chosen from the encoded
// id), point ids from the sequencer, then the three decode phases.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { SequentialAttributeEncoderType } from "../config/CompressionShared";
import { AttributesDecoder } from "./AttributesDecoder";
import { PointAttribute } from "./PointAttribute";
import { PointsSequencer } from "./PointsSequencer";
import { SequentialAttributeDecoder } from "./SequentialAttributeDecoder";
import { SequentialIntegerAttributeDecoder } from "./SequentialIntegerAttributeDecoder";
import { SequentialQuantizationAttributeDecoder } from "./SequentialQuantizationAttributeDecoder";
import { SequentialNormalAttributeDecoder } from "./SequentialNormalAttributeDecoder";

export class SequentialAttributeDecodersController extends AttributesDecoder {
    private sequentialDecoders_: Array<SequentialAttributeDecoder> =
        new Array<SequentialAttributeDecoder>();
    private pointIds_: Int32Array = new Int32Array(0);
    private sequencer_: PointsSequencer;

    constructor(sequencer: PointsSequencer) {
        super();
        this.sequencer_ = sequencer;
    }

    decodeAttributesDecoderData(buffer: DecoderBuffer): bool {
        if (!super.decodeAttributesDecoderData(buffer)) {
            return false;
        }
        let numAttributes = this.getNumAttributes();
        this.sequentialDecoders_ = new Array<SequentialAttributeDecoder>();
        for (let i = 0; i < numAttributes; i++) {
            let decoderType = buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }
            let sequentialDecoder = this.createSequentialDecoder(<i32>decoderType);
            if (sequentialDecoder == null) {
                return false;
            }
            if (!sequentialDecoder.init(this.getDecoder(), this.getAttributeId(i))) {
                return false;
            }
            this.sequentialDecoders_.push(sequentialDecoder);
        }
        return true;
    }

    decodeAttributes(buffer: DecoderBuffer): bool {
        if (!this.sequencer_.generateSequence()) {
            return false;
        }
        this.pointIds_ = this.sequencer_.getOutputPointIds();

        // Initialize point-to-attribute-value mapping for all attributes.
        let numAttributes = this.getNumAttributes();
        for (let i = 0; i < numAttributes; i++) {
            let pa = this.getDecoder().pointCloud().attribute(this.getAttributeId(i));
            if (!this.sequencer_.updatePointToAttributeIndexMapping(pa)) {
                return false;
            }
        }
        return super.decodeAttributes(buffer);
    }

    getPortableAttribute(pointAttributeId: i32): PointAttribute | null {
        let locId = this.getLocalIdForPointAttribute(pointAttributeId);
        if (locId < 0) {
            return null;
        }
        return this.sequentialDecoders_[locId].getPortableAttribute();
    }

    decodePortableAttributes(buffer: DecoderBuffer): bool {
        let numAttributes = this.getNumAttributes();
        for (let i = 0; i < numAttributes; i++) {
            if (!this.sequentialDecoders_[i].decodePortableAttribute(this.pointIds_, buffer)) {
                return false;
            }
        }
        return true;
    }

    decodeDataNeededByPortableTransforms(buffer: DecoderBuffer): bool {
        let numAttributes = this.getNumAttributes();
        for (let i = 0; i < numAttributes; i++) {
            if (!this.sequentialDecoders_[i].decodeDataNeededByPortableTransform(
                    this.pointIds_, buffer)) {
                return false;
            }
        }
        return true;
    }

    transformAttributesToOriginalFormat(): bool {
        let numAttributes = this.getNumAttributes();
        for (let i = 0; i < numAttributes; i++) {
            let sequentialDecoder = this.sequentialDecoders_[i];
            let options = this.getDecoder().options();
            if (options != null) {
                let portableAttribute = sequentialDecoder.getPortableAttribute();
                if (portableAttribute != null &&
                    options.getAttributeBool(
                        sequentialDecoder.attribute().attributeType,
                        "skip_attribute_transform", false)) {
                    // Replace the output attribute with the portable one.
                    sequentialDecoder.attribute().copyFromPoint(portableAttribute);
                    continue;
                }
            }
            if (!sequentialDecoder.transformAttributeToOriginalFormat(this.pointIds_)) {
                return false;
            }
        }
        return true;
    }

    private createSequentialDecoder(decoderType: i32): SequentialAttributeDecoder | null {
        if (decoderType == SequentialAttributeEncoderType.SEQUENTIAL_ATTRIBUTE_ENCODER_GENERIC) {
            return new SequentialAttributeDecoder();
        } else if (decoderType == SequentialAttributeEncoderType.SEQUENTIAL_ATTRIBUTE_ENCODER_INTEGER) {
            return new SequentialIntegerAttributeDecoder();
        } else if (decoderType == SequentialAttributeEncoderType.SEQUENTIAL_ATTRIBUTE_ENCODER_QUANTIZATION) {
            return new SequentialQuantizationAttributeDecoder();
        } else if (decoderType == SequentialAttributeEncoderType.SEQUENTIAL_ATTRIBUTE_ENCODER_NORMALS) {
            return new SequentialNormalAttributeDecoder();
        }
        return null;
    }
}
