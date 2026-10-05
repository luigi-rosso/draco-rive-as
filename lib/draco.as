// Public facade for the Draco mesh decoder, mirroring the Luau draco.luau:
// decodes a Draco bitstream into flat typed-array attributes plus a flat face
// index array, all in decoded-point order. Errors surface on the result's
// ok/error fields (the stub runtime cannot throw recoverably).

import { DecoderBuffer } from "./core/DecoderBuffer";
import { GeometryAttributeType } from "./attributes/GeometryAttribute";
import { Decoder } from "./Decode";
import { DecoderOptions } from "./config/DecoderOptions";
import { DataType, dataTypeLength } from "./core/DracoTypes";

export { DecoderOptions };

// One decoded attribute in the type the stream declared, numPoints *
// numComponents values; glTF primitives map their attributes by uniqueId.
export class DracoAttribute {
    uniqueId: u32 = 0;
    attributeType: i32 = GeometryAttributeType.INVALID;
    dataType: i32 = DataType.INVALID;
    numComponents: i32 = 0;
    normalized: bool = false;
    data: ArrayBuffer = new ArrayBuffer(0);

    // The values as floats: a view sharing data for float attributes, a
    // converted copy otherwise.
    unsafe toFloat32(): Float32Array {
        let dt = this.dataType;
        if (dt == DataType.FLOAT32) {
            return Float32Array.wrap(this.data);
        }
        let size = dataTypeLength(dt);
        let count = size > 0 ? this.data.byteLength / size : 0;
        let out = new Float32Array(count);
        let src = changetype<usize>(this.data);
        for (let i = 0; i < count; i++) {
            let v: f64 = 0;
            if (dt == DataType.INT8) {
                v = <f64>load<i8>(src + <usize>i);
            } else if (dt == DataType.UINT8) {
                v = <f64>load<u8>(src + <usize>i);
            } else if (dt == DataType.INT16) {
                v = <f64>load<i16>(src + (<usize>i << 1));
            } else if (dt == DataType.UINT16) {
                v = <f64>load<u16>(src + (<usize>i << 1));
            } else if (dt == DataType.INT32) {
                v = <f64>load<i32>(src + (<usize>i << 2));
            } else if (dt == DataType.UINT32) {
                v = <f64>load<u32>(src + (<usize>i << 2));
            } else if (dt == DataType.FLOAT64) {
                v = load<f64>(src + (<usize>i << 3));
            }
            unchecked(out[i] = <f32>v);
        }
        return out;
    }
}

// Decoded mesh: each attribute is a flat array of numPoints * components,
// indexed by faces (numFaces * 3). The named arrays are the first attribute
// of each type as floats; for float attributes they share memory with
// attributes[i].data, others convert on first access.
export class DracoMesh {
    ok: bool = false;
    error: string = "";
    numPoints: i32 = 0;
    numFaces: i32 = 0;
    faces: Int32Array = new Int32Array(0);
    attributes: Array<DracoAttribute> = new Array<DracoAttribute>();
    private namedFloats: Map<i32, Float32Array> = new Map<i32, Float32Array>();

    get positions(): Float32Array? {
        return this.named(GeometryAttributeType.POSITION);
    }

    get normals(): Float32Array? {
        return this.named(GeometryAttributeType.NORMAL);
    }

    get texcoords(): Float32Array? {
        return this.named(GeometryAttributeType.TEX_COORD);
    }

    get colors(): Float32Array? {
        return this.named(GeometryAttributeType.COLOR);
    }

    attributeById(uniqueId: u32): DracoAttribute? {
        for (let i = 0; i < this.attributes.length; i++) {
            let att = this.attributes[i];
            if (att.uniqueId == uniqueId) {
                return att;
            }
        }
        return null;
    }

    private named(type: i32): Float32Array? {
        if (this.namedFloats.has(type)) {
            return this.namedFloats.get(type);
        }
        for (let i = 0; i < this.attributes.length; i++) {
            let att = this.attributes[i];
            if (att.attributeType == type) {
                let floats = att.toFloat32();
                this.namedFloats.set(type, floats);
                return floats;
            }
        }
        return null;
    }
}

// Decodes a Draco mesh bitstream (a .drc file's bytes, or the buffer from a
// glTF KHR_draco_mesh_compression bufferView).
export unsafe function decode(
    data: ArrayBuffer, options: DecoderOptions = new DecoderOptions()): DracoMesh {
    let out = new DracoMesh();

    let db = new DecoderBuffer();
    db.init(data);

    let decoder = new Decoder(options);
    let result = decoder.decodeMeshFromBuffer(db);
    let mesh = result.mesh;
    if (!result.status.ok() || mesh == null) {
        out.error = result.status.errorMsg;
        return out;
    }

    let numPoints = mesh.numPoints();
    let numFaces = mesh.numFaces();
    out.numPoints = numPoints;
    out.numFaces = numFaces;

    // Faces hold point ids, 3 per corner; copy only when the mesh kept spare
    // capacity past the decoded range.
    let faces = mesh.faces;
    if (faces.length != numFaces * 3) {
        faces = new Int32Array(numFaces * 3);
        memory.copy(faces.dataStart, mesh.faces.dataStart, <usize>faces.length << 2);
    }
    out.faces = faces;

    for (let i = 0; i < mesh.numAttributes(); i++) {
        let att = mesh.attribute(i);
        let raw = new DracoAttribute();
        raw.uniqueId = att.uniqueId;
        raw.attributeType = att.attributeType;
        raw.dataType = att.dataType;
        raw.numComponents = att.numComponents;
        raw.normalized = att.normalized;
        raw.data = att.extractRaw(numPoints);
        out.attributes.push(raw);
    }

    out.ok = true;
    return out;
}
