// Ported from draco compression/attributes/attributes_decoder.h/.cc
// (bitstream >= 2.2 subset). Base for attributes decoders: reads the attribute
// headers and creates the PointAttributes.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType, dataTypeLength } from "../core/DracoTypes";
import { GeometryAttribute, GeometryAttributeType } from "./GeometryAttribute";
import { PointAttribute } from "./PointAttribute";
import { Mesh } from "../mesh/Mesh";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

export class AttributesDecoder {
    private pointAttributeIds_: Array<i32> = new Array<i32>();
    // Inverse of pointAttributeIds_: point attribute id -> local id.
    private pointAttributeToLocalIdMap_: Array<i32> = new Array<i32>();
    private pointCloudDecoder_: PointCloudDecoder | null = null;
    private pointCloud_: Mesh | null = null;

    init(decoder: PointCloudDecoder, pointCloud: Mesh): bool {
        this.pointCloudDecoder_ = decoder;
        this.pointCloud_ = pointCloud;
        return true;
    }

    decodeAttributesDecoderData(buffer: DecoderBuffer): bool {
        let numAttributes = <i32>buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        if (numAttributes <= 0) {
            return false;
        }
        if (numAttributes > 5 * buffer.remainingSize()) {
            return false; // Unreasonably high attribute count.
        }

        let pc = this.pointCloud_!;
        this.pointAttributeIds_ = new Array<i32>(numAttributes);

        for (let i = 0; i < numAttributes; i++) {
            let attType = buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }
            let dataType = <i32>buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }
            let numComponents = <i32>buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }
            let normalized = buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }

            if (attType >= <u32>GeometryAttributeType.NAMED_ATTRIBUTES_COUNT) {
                return false;
            }
            if (dataType == DataType.INVALID || dataType >= DataType.TYPES_COUNT) {
                return false;
            }
            if (numComponents == 0) {
                return false;
            }

            let ga = new GeometryAttribute();
            ga.init(
                <i32>attType, null, numComponents, dataType, normalized > 0,
                dataTypeLength(dataType) * numComponents, 0);

            let uniqueId = buffer.decodeVarintUint32();
            if (buffer.err) {
                return false;
            }
            ga.uniqueId = uniqueId;

            let pa = new PointAttribute(ga);
            let attId = pc.addAttribute(pa);
            pc.attribute(attId).uniqueId = uniqueId;
            this.pointAttributeIds_[i] = attId;

            // Update the inverse map.
            while (this.pointAttributeToLocalIdMap_.length <= attId) {
                this.pointAttributeToLocalIdMap_.push(-1);
            }
            this.pointAttributeToLocalIdMap_[attId] = i;
        }
        return true;
    }

    getAttributeId(i: i32): i32 {
        return this.pointAttributeIds_[i];
    }

    getNumAttributes(): i32 {
        return this.pointAttributeIds_.length;
    }

    getDecoder(): PointCloudDecoder {
        return this.pointCloudDecoder_!;
    }

    getPointCloud(): Mesh {
        return this.pointCloud_!;
    }

    decodeAttributes(buffer: DecoderBuffer): bool {
        if (!this.decodePortableAttributes(buffer)) {
            return false;
        }
        if (!this.decodeDataNeededByPortableTransforms(buffer)) {
            return false;
        }
        if (!this.transformAttributesToOriginalFormat()) {
            return false;
        }
        return true;
    }

    getLocalIdForPointAttribute(pointAttributeId: i32): i32 {
        if (pointAttributeId < 0 ||
            pointAttributeId >= this.pointAttributeToLocalIdMap_.length) {
            return -1;
        }
        return this.pointAttributeToLocalIdMap_[pointAttributeId];
    }

    // Virtuals overridden by derived classes.
    getPortableAttribute(pointAttributeId: i32): PointAttribute | null {
        return null;
    }

    decodePortableAttributes(buffer: DecoderBuffer): bool {
        return false;
    }

    decodeDataNeededByPortableTransforms(buffer: DecoderBuffer): bool {
        return true;
    }

    transformAttributesToOriginalFormat(): bool {
        return true;
    }
}
