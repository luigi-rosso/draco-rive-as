// Ported from draco
// compression/attributes/sequential_normal_attribute_decoder.h/.cc
// (bitstream >= 2.2 subset). Normals decode as two octahedral components and
// expand to float32 unit vectors via the octahedron transform. Only the
// canonicalized octahedron prediction transform is ported (the plain variant
// left the encoder before bitstream 2.2).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType } from "../core/DracoTypes";
import { PredictionSchemeTransformType } from "../config/CompressionShared";
import { AttributeOctahedronTransform } from "./AttributeOctahedronTransform";
import { SequentialIntegerAttributeDecoder } from "./SequentialIntegerAttributeDecoder";
import { PredictionSchemeDecoder } from "../prediction/PredictionSchemeDecoder";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "../prediction/PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";
import { createPredictionSchemeForDecoderNormalOcta } from "../prediction/CreatePredictionSchemeForDecoder";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

export class SequentialNormalAttributeDecoder extends SequentialIntegerAttributeDecoder {
    private octahedralTransform_: AttributeOctahedronTransform =
        new AttributeOctahedronTransform();

    init(decoder: PointCloudDecoder, attributeId: i32): bool {
        if (!super.init(decoder, attributeId)) {
            return false;
        }
        // This decoder works only for 3-component float32 normal vectors.
        if (this.attribute().numComponents != 3) {
            return false;
        }
        if (this.attribute().dataType != DataType.FLOAT32) {
            return false;
        }
        return true;
    }

    // Normals quantize into two octahedral components.
    protected getNumValueComponents(): i32 {
        return 2;
    }

    decodeDataNeededByPortableTransform(
        pointIds: Int32Array, buffer: DecoderBuffer): bool {
        let portable = this.getPortableAttribute();
        if (portable == null) {
            return false;
        }
        if (!this.octahedralTransform_.decodeParameters(portable, buffer)) {
            return false;
        }
        return this.octahedralTransform_.transferToAttribute(this.portableAttribute()!);
    }

    protected storeValues(numValues: i32): bool {
        let portable = this.getPortableAttribute();
        if (portable == null) {
            return false;
        }
        return this.octahedralTransform_.inverseTransformAttribute(
            portable, this.attribute());
    }

    protected createIntPredictionScheme(
        method: i32, transformType: i32): PredictionSchemeDecoder | null {
        if (transformType ==
            PredictionSchemeTransformType.PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON_CANONICALIZED) {
            let transform =
                new PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform();
            return createPredictionSchemeForDecoderNormalOcta(
                method, this.attributeId(), this.decoder(), transform);
        }
        // PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON is pre-2.2 only.
        return null;
    }
}
