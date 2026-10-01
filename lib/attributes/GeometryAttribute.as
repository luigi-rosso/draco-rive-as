// Ported from draco.js attributes/GeometryAttribute.js via the Luau port. The
// JS getters expose plain data members, so they are public fields here.

import { DataBuffer } from "../core/DataBuffer";
import { DataType } from "../core/DracoTypes";

export enum GeometryAttributeType {
    INVALID = -1,
    POSITION = 0,
    NORMAL = 1,
    COLOR = 2,
    TEX_COORD = 3,
    GENERIC = 4,
    NAMED_ATTRIBUTES_COUNT = 5,
}

export class GeometryAttribute {
    buffer: DataBuffer? = null;
    numComponents: i32 = 1;
    dataType: i32 = DataType.FLOAT32;
    normalized: bool = false;
    byteStride: i32 = 0;
    byteOffset: i32 = 0;
    attributeType: i32 = GeometryAttributeType.INVALID;
    uniqueId: u32 = 0;

    init(
        attributeType: i32, buf: DataBuffer?, numComponents: i32, dataType: i32,
        normalized: bool, byteStride: i32, byteOffset: i32): void {
        this.buffer = buf;
        this.numComponents = numComponents;
        this.dataType = dataType;
        this.normalized = normalized;
        this.byteStride = byteStride;
        this.byteOffset = byteOffset;
        this.attributeType = attributeType;
    }

    // Returns a Uint8Array view of the buffer starting at the attribute entry.
    getAddress(attIndex: i32): Uint8Array {
        let bytePos = this.byteOffset + this.byteStride * attIndex;
        let buf = this.buffer;
        if (buf == null) {
            return new Uint8Array(0);
        }
        return buf.data().subarray(bytePos);
    }

    copyFrom(srcAtt: GeometryAttribute): bool {
        this.numComponents = srcAtt.numComponents;
        this.dataType = srcAtt.dataType;
        this.normalized = srcAtt.normalized;
        this.byteStride = srcAtt.byteStride;
        this.byteOffset = srcAtt.byteOffset;
        this.attributeType = srcAtt.attributeType;
        this.uniqueId = srcAtt.uniqueId;

        let srcBuf = srcAtt.buffer;
        if (srcBuf == null) {
            this.buffer = null;
        } else {
            let buf = this.buffer;
            if (buf == null) {
                return false;
            }
            buf.update(srcBuf.data(), srcBuf.dataSize());
        }
        return true;
    }

    resetBuffer(buf: DataBuffer, byteStride: i32, byteOffset: i32): void {
        this.buffer = buf;
        this.byteStride = byteStride;
        this.byteOffset = byteOffset;
    }
}
