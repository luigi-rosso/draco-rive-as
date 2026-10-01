// Ported from draco.js attributes/PointAttribute.js via the Luau port. Extends
// GeometryAttribute.
//
// AS deviations from the Luau (documented in the phase B manifest):
//  * The Luau PointAttribute:init(5 args) shadows GeometryAttribute:init; AS
//    cannot overload an inherited method, so it is `initValues` here.
//  * indicesMap() is always a Uint32Array (empty under identity mapping); the
//    Luau swapped a jsarray in for the identity case but never read it.
//  * extractTo(TypedArrayClass, n) becomes one concrete method per output
//    element type.

import { GeometryAttribute } from "./GeometryAttribute";
import { AttributeTransformData } from "./AttributeTransformData";
import { kInvalidAttributeValueIndex } from "./GeometryIndices";
import { DataBuffer } from "../core/DataBuffer";
import { DataType, dataTypeLength } from "../core/DracoTypes";

export class PointAttribute extends GeometryAttribute {
    private _identityMapping: bool = false;
    private _numUniqueEntries: i32 = 0;
    private _indicesMap: Uint32Array = new Uint32Array(0);
    private _attributeBuffer: DataBuffer? = null;
    private _attributeTransformData: AttributeTransformData? = null;

    constructor(geometryAttribute: GeometryAttribute? = null) {
        super();
        if (geometryAttribute != null) {
            this.buffer = geometryAttribute.buffer;
            this.numComponents = geometryAttribute.numComponents;
            this.dataType = geometryAttribute.dataType;
            this.normalized = geometryAttribute.normalized;
            this.byteStride = geometryAttribute.byteStride;
            this.byteOffset = geometryAttribute.byteOffset;
            this.attributeType = geometryAttribute.attributeType;
            this.uniqueId = geometryAttribute.uniqueId;
        }
    }

    // Luau PointAttribute:init; renamed to avoid overloading the inherited
    // GeometryAttribute.init.
    initValues(
        attributeType: i32, numComponents: i32, dataType: i32, normalized: bool,
        numAttributeValues: i32): void {
        let attBuffer = new DataBuffer();
        this._attributeBuffer = attBuffer;
        let byteStride = dataTypeLength(dataType) * numComponents;
        this.init(attributeType, attBuffer, numComponents, dataType, normalized, byteStride, 0);
        this.reset(numAttributeValues);
        this.setIdentityMapping();
    }

    reset(numAttributeValues: i32): bool {
        let attBuffer = this._attributeBuffer;
        if (attBuffer == null) {
            attBuffer = new DataBuffer();
            this._attributeBuffer = attBuffer;
        }
        let entrySize = dataTypeLength(this.dataType) * this.numComponents;
        attBuffer.update(null, numAttributeValues * entrySize);
        this.resetBuffer(attBuffer, entrySize, 0);
        this._numUniqueEntries = numAttributeValues;
        return true;
    }

    size(): i32 {
        return this._numUniqueEntries;
    }

    mappedIndex(pointIndex: i32): u32 {
        if (this._identityMapping) {
            return <u32>pointIndex;
        }
        return this._indicesMap[pointIndex];
    }

    isMappingIdentity(): bool {
        return this._identityMapping;
    }

    indicesMapSize(): i32 {
        if (this._identityMapping) {
            return 0;
        }
        return this._indicesMap.length;
    }

    // Direct access to the explicit point->value index map.
    indicesMap(): Uint32Array {
        return this._indicesMap;
    }

    // Implicit mapping: point index equals attribute entry index.
    setIdentityMapping(): void {
        this._identityMapping = true;
        this._indicesMap = new Uint32Array(0);
    }

    setExplicitMapping(numPoints: i32): void {
        this._identityMapping = false;
        // Must be unsigned so the 0xFFFFFFFF invalid sentinel round-trips intact.
        let map = new Uint32Array(numPoints);
        map.fill(kInvalidAttributeValueIndex);
        this._indicesMap = map;
    }

    setAttributeTransformData(transformData: AttributeTransformData?): void {
        this._attributeTransformData = transformData;
    }

    // Mirrors C++ PointAttribute::ConvertValue(); writes numComponents values
    // into outVal as float64 (all source types are exactly representable).
    unsafe convertValue(attIndex: i32, outVal: Float64Array): void {
        let bytePos = this.byteOffset + this.byteStride * attIndex;
        let buf = this.buffer;
        if (buf == null) {
            return;
        }
        let base = buf.data().dataStart + <usize>bytePos;
        let dt = this.dataType;
        let nc = this.numComponents;
        if (dt == DataType.FLOAT32) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<f32>(base + (<usize>i << 2));
            }
        } else if (dt == DataType.INT32) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<i32>(base + (<usize>i << 2));
            }
        } else if (dt == DataType.UINT32) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<u32>(base + (<usize>i << 2));
            }
        } else if (dt == DataType.INT8) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<i8>(base + <usize>i);
            }
        } else if (dt == DataType.UINT8) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<u8>(base + <usize>i);
            }
        } else if (dt == DataType.INT16) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<i16>(base + (<usize>i << 1));
            }
        } else if (dt == DataType.UINT16) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = <f64>load<u16>(base + (<usize>i << 1));
            }
        } else if (dt == DataType.FLOAT64) {
            for (let i = 0; i < nc; i++) {
                outVal[i] = load<f64>(base + (<usize>i << 3));
            }
        } else {
            for (let i = 0; i < nc; i++) {
                outVal[i] = 0;
            }
        }
    }

    // Per-component read as f64 for the extract loops (attIndex pre-mapped).
    private unsafe readComponent(attIndex: i32, component: i32): f64 {
        let buf = this.buffer;
        if (buf == null) {
            return 0;
        }
        let base = buf.data().dataStart + <usize>(this.byteOffset + this.byteStride * attIndex);
        let dt = this.dataType;
        if (dt == DataType.FLOAT32) {
            return <f64>load<f32>(base + (<usize>component << 2));
        } else if (dt == DataType.INT32) {
            return <f64>load<i32>(base + (<usize>component << 2));
        } else if (dt == DataType.UINT32) {
            return <f64>load<u32>(base + (<usize>component << 2));
        } else if (dt == DataType.INT8) {
            return <f64>load<i8>(base + <usize>component);
        } else if (dt == DataType.UINT8) {
            return <f64>load<u8>(base + <usize>component);
        } else if (dt == DataType.INT16) {
            return <f64>load<i16>(base + (<usize>component << 1));
        } else if (dt == DataType.UINT16) {
            return <f64>load<u16>(base + (<usize>component << 1));
        } else if (dt == DataType.FLOAT64) {
            return load<f64>(base + (<usize>component << 3));
        }
        return 0;
    }

    private extractIndex(i: i32): i32 {
        return this._identityMapping ? i : <i32>unchecked(this._indicesMap[i]);
    }

    unsafe extractToFloat32(numPoints: i32): Float32Array {
        let nc = this.numComponents;
        let out = new Float32Array(numPoints * nc);
        let buf = this.buffer;
        if (buf == null || numPoints == 0) {
            return out;
        }
        if (this.dataType == DataType.FLOAT32) {
            // Common case: float source, tight or strided copy.
            let base = buf.data().dataStart + <usize>this.byteOffset;
            let stride = <usize>this.byteStride;
            if (this._identityMapping && stride == (<usize>nc << 2)) {
                memory.copy(out.dataStart, base, <usize>(numPoints * nc) << 2);
                return out;
            }
            let outPtr = out.dataStart;
            for (let i = 0; i < numPoints; i++) {
                let src = base + stride * <usize>this.extractIndex(i);
                for (let j = 0; j < nc; j++) {
                    store<f32>(outPtr, load<f32>(src + (<usize>j << 2)));
                    outPtr += 4;
                }
            }
            return out;
        }
        for (let i = 0; i < numPoints; i++) {
            let attIndex = this.extractIndex(i);
            for (let j = 0; j < nc; j++) {
                unchecked(out[i * nc + j] = <f32>this.readComponent(attIndex, j));
            }
        }
        return out;
    }

    extractToInt32(numPoints: i32): Int32Array {
        let nc = this.numComponents;
        let out = new Int32Array(numPoints * nc);
        if (this.buffer == null || numPoints == 0) {
            return out;
        }
        for (let i = 0; i < numPoints; i++) {
            let attIndex = this.extractIndex(i);
            for (let j = 0; j < nc; j++) {
                out[i * nc + j] = <i32>this.readComponent(attIndex, j);
            }
        }
        return out;
    }

    extractToUint32(numPoints: i32): Uint32Array {
        let nc = this.numComponents;
        let out = new Uint32Array(numPoints * nc);
        if (this.buffer == null || numPoints == 0) {
            return out;
        }
        for (let i = 0; i < numPoints; i++) {
            let attIndex = this.extractIndex(i);
            for (let j = 0; j < nc; j++) {
                out[i * nc + j] = <u32>this.readComponent(attIndex, j);
            }
        }
        return out;
    }

    extractToUint16(numPoints: i32): Uint16Array {
        let nc = this.numComponents;
        let out = new Uint16Array(numPoints * nc);
        if (this.buffer == null || numPoints == 0) {
            return out;
        }
        for (let i = 0; i < numPoints; i++) {
            let attIndex = this.extractIndex(i);
            for (let j = 0; j < nc; j++) {
                out[i * nc + j] = <u16><u32>this.readComponent(attIndex, j);
            }
        }
        return out;
    }

    copyFromPoint(srcAtt: PointAttribute): void {
        if (this.buffer == null) {
            let attBuffer = new DataBuffer();
            this._attributeBuffer = attBuffer;
            this.resetBuffer(attBuffer, 0, 0);
        }
        if (!this.copyFrom(srcAtt)) {
            return;
        }
        this._identityMapping = srcAtt._identityMapping;
        this._numUniqueEntries = srcAtt._numUniqueEntries;
        this._indicesMap = srcAtt._indicesMap.slice();
        this._attributeTransformData = srcAtt._attributeTransformData;
    }
}
