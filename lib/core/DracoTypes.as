// Ported from draco.js core/DracoTypes.js (draco_types.h/cc).

export enum DataType {
    INVALID = 0,
    INT8 = 1,
    UINT8 = 2,
    INT16 = 3,
    UINT16 = 4,
    INT32 = 5,
    UINT32 = 6,
    INT64 = 7,
    UINT64 = 8,
    FLOAT32 = 9,
    FLOAT64 = 10,
    BOOL = 11,
    TYPES_COUNT = 12,
}

export function dataTypeLength(dt: i32): i32 {
    if (dt == DataType.INT8 || dt == DataType.UINT8) {
        return 1;
    } else if (dt == DataType.INT16 || dt == DataType.UINT16) {
        return 2;
    } else if (dt == DataType.INT32 || dt == DataType.UINT32) {
        return 4;
    } else if (dt == DataType.INT64 || dt == DataType.UINT64) {
        return 8;
    } else if (dt == DataType.FLOAT32) {
        return 4;
    } else if (dt == DataType.FLOAT64) {
        return 8;
    } else if (dt == DataType.BOOL) {
        return 1;
    }
    return -1;
}
