// Ported from draco.js attributes/AttributeTransformData.js via the Luau port.
// Stores transform parameters in a DataBuffer. The Luau API took a type-name
// string per write; AS gets one typed method per parameter type instead (the
// decoders only ever append int32 and float32).

import { DataBuffer } from "../core/DataBuffer";
import { AttributeTransformType } from "./AttributeTransformType";

export class AttributeTransformData {
    transformType: i32 = AttributeTransformType.INVALID;
    private _buffer: DataBuffer = new DataBuffer();

    private grow(byteOffset: i32, size: i32): usize {
        let sizeNeeded = byteOffset + size;
        if (sizeNeeded > this._buffer.dataSize()) {
            this._buffer.resize(sizeNeeded);
        }
        return this._buffer.data().dataStart + <usize>byteOffset;
    }

    unsafe setInt32(byteOffset: i32, value: i32): void {
        store<i32>(this.grow(byteOffset, 4), value);
    }

    unsafe setFloat32(byteOffset: i32, value: f32): void {
        store<f32>(this.grow(byteOffset, 4), value);
    }

    appendInt32(value: i32): void {
        this.setInt32(this._buffer.dataSize(), value);
    }

    appendFloat32(value: f32): void {
        this.setFloat32(this._buffer.dataSize(), value);
    }
}
