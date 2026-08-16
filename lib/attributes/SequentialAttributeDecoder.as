// Ported from draco compression/attributes/sequential_attribute_decoder.h/.cc
// (bitstream >= 2.2 subset). Base class for decoding one attribute's values.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointAttribute } from "./PointAttribute";
import { PredictionSchemeDecoder } from "../prediction/PredictionSchemeDecoder";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

export class SequentialAttributeDecoder {
    protected decoder_: PointCloudDecoder | null = null;
    protected attribute_: PointAttribute | null = null;
    protected attributeId_: i32 = -1;
    protected portableAttribute_: PointAttribute | null = null;

    init(decoder: PointCloudDecoder, attributeId: i32): bool {
        this.decoder_ = decoder;
        this.attribute_ = decoder.pointCloud().attribute(attributeId);
        this.attributeId_ = attributeId;
        return true;
    }

    decodePortableAttribute(pointIds: Int32Array, buffer: DecoderBuffer): bool {
        let attribute = this.attribute_!;
        if (attribute.numComponents <= 0) {
            return false;
        }
        if (!attribute.reset(pointIds.length)) {
            return false;
        }
        return this.decodeValues(pointIds, buffer);
    }

    // No-ops by default; subclasses with a transform override these.
    decodeDataNeededByPortableTransform(
        pointIds: Int32Array, buffer: DecoderBuffer): bool {
        return true;
    }

    transformAttributeToOriginalFormat(pointIds: Int32Array): bool {
        return true;
    }

    getPortableAttribute(): PointAttribute | null {
        // Copy the point->value index mapping from the final attribute to the
        // portable one.
        let attribute = this.attribute_!;
        let portable = this.portableAttribute_;
        if (!attribute.isMappingIdentity() && portable != null &&
            portable.isMappingIdentity()) {
            let size = attribute.indicesMapSize();
            portable.setExplicitMapping(size);
            let src = attribute.indicesMap();
            let dst = portable.indicesMap();
            memory.copy(dst.dataStart, src.dataStart, <usize>size << 2);
        }
        return this.portableAttribute_;
    }

    attribute(): PointAttribute {
        return this.attribute_!;
    }

    attributeId(): i32 {
        return this.attributeId_;
    }

    decoder(): PointCloudDecoder {
        return this.decoder_!;
    }

    protected initPredictionScheme(ps: PredictionSchemeDecoder): bool {
        let decoder = this.decoder_!;
        for (let i = 0; i < ps.getNumParentAttributes(); i++) {
            let attId = decoder.pointCloud().getNamedAttributeId(ps.getParentAttributeType(i));
            if (attId == -1) {
                return false; // Requested attribute does not exist.
            }
            let pa = decoder.getPortableAttribute(attId);
            if (pa == null || !ps.setParentAttribute(pa)) {
                return false;
            }
        }
        return true;
    }

    // Decodes raw attribute values in their original format.
    decodeValues(pointIds: Int32Array, buffer: DecoderBuffer): bool {
        let attribute = this.attribute_!;
        let numValues = pointIds.length;
        let entrySize = attribute.byteStride;
        let total = numValues * entrySize;
        if (buffer.remainingSize() < total) {
            return false;
        }
        // One contiguous span straight from the input buffer.
        let src = buffer.dataHead();
        attribute.buffer!.write(0, src, total);
        buffer.advance(total);
        return true;
    }

    protected setPortableAttribute(att: PointAttribute): void {
        this.portableAttribute_ = att;
    }

    protected portableAttribute(): PointAttribute | null {
        return this.portableAttribute_;
    }
}
