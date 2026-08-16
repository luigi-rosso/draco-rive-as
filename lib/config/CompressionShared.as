// Ported from draco.js compression/config/CompressionShared.js.

export const kDracoPointCloudBitstreamVersionMajor: i32 = 2;
export const kDracoPointCloudBitstreamVersionMinor: i32 = 3;
export const kDracoMeshBitstreamVersionMajor: i32 = 2;
export const kDracoMeshBitstreamVersionMinor: i32 = 2;

export function DRACO_BITSTREAM_VERSION(major: u32, minor: u32): u32 {
    return (major << 8) | minor;
}

export class DracoHeader {
    dracoString: Int8Array = new Int8Array(5);
    versionMajor: i32 = 0;
    versionMinor: i32 = 0;
    encoderType: i32 = 0;
    encoderMethod: i32 = 0;
    flags: i32 = 0;
}

export enum EncodedGeometryType {
    INVALID_GEOMETRY_TYPE = -1,
    POINT_CLOUD = 0,
    TRIANGULAR_MESH = 1,
    NUM_ENCODED_GEOMETRY_TYPES = 2,
}

export enum MeshEncoderMethod {
    MESH_SEQUENTIAL_ENCODING = 0,
    MESH_EDGEBREAKER_ENCODING = 1,
}

export enum SequentialAttributeEncoderType {
    SEQUENTIAL_ATTRIBUTE_ENCODER_GENERIC = 0,
    SEQUENTIAL_ATTRIBUTE_ENCODER_INTEGER = 1,
    SEQUENTIAL_ATTRIBUTE_ENCODER_QUANTIZATION = 2,
    SEQUENTIAL_ATTRIBUTE_ENCODER_NORMALS = 3,
}

export enum PredictionSchemeMethod {
    PREDICTION_NONE = -2,
    PREDICTION_UNDEFINED = -1,
    PREDICTION_DIFFERENCE = 0,
    MESH_PREDICTION_PARALLELOGRAM = 1,
    MESH_PREDICTION_MULTI_PARALLELOGRAM = 2,
    MESH_PREDICTION_TEX_COORDS_DEPRECATED = 3,
    MESH_PREDICTION_CONSTRAINED_MULTI_PARALLELOGRAM = 4,
    MESH_PREDICTION_TEX_COORDS_PORTABLE = 5,
    MESH_PREDICTION_GEOMETRIC_NORMAL = 6,
    NUM_PREDICTION_SCHEMES = 7,
}

export enum PredictionSchemeTransformType {
    PREDICTION_TRANSFORM_NONE = -1,
    PREDICTION_TRANSFORM_DELTA = 0,
    PREDICTION_TRANSFORM_WRAP = 1,
    PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON = 2,
    PREDICTION_TRANSFORM_NORMAL_OCTAHEDRON_CANONICALIZED = 3,
    NUM_PREDICTION_SCHEME_TRANSFORM_TYPES = 4,
}

export enum MeshTraversalMethod {
    MESH_TRAVERSAL_DEPTH_FIRST = 0,
    MESH_TRAVERSAL_PREDICTION_DEGREE = 1,
    NUM_TRAVERSAL_METHODS = 2,
}

export enum MeshEdgebreakerConnectivityEncodingMethod {
    MESH_EDGEBREAKER_STANDARD_ENCODING = 0,
    // Deprecated.
    MESH_EDGEBREAKER_PREDICTIVE_ENCODING = 1,
    MESH_EDGEBREAKER_VALENCE_ENCODING = 2,
}

export enum NormalPredictionMode {
    // To be deprecated.
    ONE_TRIANGLE = 0,
    TRIANGLE_AREA = 1,
}

export enum SymbolCodingMethod {
    SYMBOL_CODING_TAGGED = 0,
    SYMBOL_CODING_RAW = 1,
    NUM_SYMBOL_CODING_METHODS = 2,
}

export const METADATA_FLAG_MASK: i32 = 0x8000;
