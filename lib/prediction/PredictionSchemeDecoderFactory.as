// Ported from draco prediction_scheme_decoder_factory.h /
// mesh_prediction_scheme_decoder_factory.h, collapsed to the monomorphized
// combos the decoder subset instantiates. Phase C reads the transform type
// from the bitstream, builds the matching transform, resolves the mesh data
// (attribute corner table when present, base corner table otherwise) and calls
// the creator for that transform; a null return means fall back to the
// matching delta decoder.

import { PointAttribute } from "../attributes/PointAttribute";
import { PredictionSchemeMethod } from "../config/CompressionShared";
import { MeshPredictionSchemeData } from "./MeshPredictionSchemeData";
import { PredictionSchemeDecoder } from "./PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "./PredictionSchemeWrapDecodingTransform";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "./PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";
import {
    PredictionSchemeDeltaDecoderWrap,
    PredictionSchemeDeltaDecoderNormalOcta,
} from "./PredictionSchemeDeltaDecoder";
import { MeshPredictionSchemeParallelogramDecoder } from "./MeshPredictionSchemeParallelogramDecoder";
import { MeshPredictionSchemeTexCoordsPortableDecoder } from "./MeshPredictionSchemeTexCoordsPortableDecoder";
import { MeshPredictionSchemeGeometricNormalDecoder } from "./MeshPredictionSchemeGeometricNormalDecoder";

// Mesh prediction schemes paired with the wrap transform (integer and UV
// attributes). Unsupported methods return null (delta fallback).
export function createMeshPredictionSchemeWrap(
    method: i32, attribute: PointAttribute?,
    transform: PredictionSchemeWrapDecodingTransform,
    meshData: MeshPredictionSchemeData): PredictionSchemeDecoder? {
    if (method == PredictionSchemeMethod.MESH_PREDICTION_PARALLELOGRAM) {
        return new MeshPredictionSchemeParallelogramDecoder(attribute, transform, meshData);
    } else if (method == PredictionSchemeMethod.MESH_PREDICTION_TEX_COORDS_PORTABLE) {
        return new MeshPredictionSchemeTexCoordsPortableDecoder(attribute, transform, meshData);
    }
    // MULTI_PARALLELOGRAM and CONSTRAINED_MULTI_PARALLELOGRAM are not in the
    // decoded subset.
    return null;
}

// Octahedral normal transforms only pair with geometric normal prediction.
export function createMeshPredictionSchemeNormalOcta(
    method: i32, attribute: PointAttribute?,
    transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform,
    meshData: MeshPredictionSchemeData): PredictionSchemeDecoder? {
    if (method == PredictionSchemeMethod.MESH_PREDICTION_GEOMETRIC_NORMAL) {
        return new MeshPredictionSchemeGeometricNormalDecoder(attribute, transform, meshData);
    }
    return null;
}

export function createDeltaDecoderWrap(
    attribute: PointAttribute?,
    transform: PredictionSchemeWrapDecodingTransform): PredictionSchemeDecoder {
    return new PredictionSchemeDeltaDecoderWrap(attribute, transform);
}

export function createDeltaDecoderNormalOcta(
    attribute: PointAttribute?,
    transform: PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform): PredictionSchemeDecoder {
    return new PredictionSchemeDeltaDecoderNormalOcta(attribute, transform);
}
