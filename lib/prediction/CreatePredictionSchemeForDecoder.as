// Ported from draco prediction_scheme_decoder_factory.h's
// CreatePredictionSchemeForDecoder, monomorphized per transform like the rest
// of the prediction layer: resolves the mesh data from the decoder and falls
// back to the delta decoder when no mesh scheme applies.

import { EncodedGeometryType, PredictionSchemeMethod } from "../config/CompressionShared";
import { CornerTableBase } from "../mesh/CornerTable";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "./PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";
import {
    createDeltaDecoderNormalOcta,
    createDeltaDecoderWrap,
    createMeshPredictionSchemeNormalOcta,
    createMeshPredictionSchemeWrap,
} from "./PredictionSchemeDecoderFactory";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

// Builds the mesh data for the attribute, preferring the attribute corner
// table; null when the decoder has no connectivity for the attribute.
function resolveMeshData(
    decoder: PointCloudDecoder, attId: i32): MeshPredictionSchemeData | null {
    if (decoder.getGeometryType() != EncodedGeometryType.TRIANGULAR_MESH) {
        return null;
    }
    let cornerTable = decoder.getCornerTable();
    let encodingData = decoder.getAttributeEncodingData(attId);
    if (cornerTable == null || encodingData == null) {
        return null;
    }
    let table: CornerTableBase;
    let attCornerTable = decoder.getAttributeCornerTable(attId);
    if (attCornerTable != null) {
        table = attCornerTable;
    } else {
        table = cornerTable;
    }
    let meshData = new MeshPredictionSchemeData();
    meshData.set(
        decoder.pointCloud(), table,
        encodingData.encodedAttributeValueIndexToCornerMap,
        encodingData.vertexToEncodedAttributeValueIndexMap);
    return meshData;
}

export function createPredictionSchemeForDecoderWrap(
    method: i32, attId: i32, decoder: PointCloudDecoder,
    transform: PredictionSchemeWrapDecodingTransform): PredictionSchemeDecoder | null {
    if (method == PredictionSchemeMethod.PREDICTION_NONE) {
        return null;
    }
    let att = decoder.pointCloud().attribute(attId);
    let meshData = resolveMeshData(decoder, attId);
    if (meshData != null) {
        let ret = createMeshPredictionSchemeWrap(method, att, transform, meshData);
        if (ret != null) {
            return ret;
        }
    }
    return createDeltaDecoderWrap(att, transform);
}

export function createPredictionSchemeForDecoderNormalOcta(
    method: i32, attId: i32, decoder: PointCloudDecoder,
    transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform): PredictionSchemeDecoder | null {
    if (method == PredictionSchemeMethod.PREDICTION_NONE) {
        return null;
    }
    let att = decoder.pointCloud().attribute(attId);
    let meshData = resolveMeshData(decoder, attId);
    if (meshData != null) {
        let ret = createMeshPredictionSchemeNormalOcta(method, att, transform, meshData);
        if (ret != null) {
            return ret;
        }
    }
    return createDeltaDecoderNormalOcta(att, transform);
}
