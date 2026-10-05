// Public facade for the Draco mesh decoder, mirroring the Luau draco.luau:
// decodes a Draco bitstream into flat typed-array attributes plus a flat face
// index array, all in decoded-point order. Errors surface on the result's
// ok/error fields (the stub runtime cannot throw recoverably).

import { DecoderBuffer } from "./core/DecoderBuffer";
import { GeometryAttributeType } from "./attributes/GeometryAttribute";
import { Decoder } from "./Decode";
import { DataType } from "./core/DracoTypes";
import { Mesh } from "./mesh/Mesh";

// One decoded attribute in the type the stream declared, numPoints *
// numComponents values; glTF primitives map their attributes by uniqueId.
export class DracoAttribute {
    uniqueId: u32 = 0;
    attributeType: i32 = GeometryAttributeType.INVALID;
    dataType: i32 = DataType.INVALID;
    numComponents: i32 = 0;
    normalized: bool = false;
    data: ArrayBuffer = new ArrayBuffer(0);
}

// Decoded mesh: each attribute is a flat typed array of numPoints *
// components, indexed by faces (numFaces * 3).
export class DracoMesh {
    ok: bool = false;
    error: string = "";
    numPoints: i32 = 0;
    numFaces: i32 = 0;
    faces: Int32Array = new Int32Array(0);
    positions: Float32Array? = null;
    normals: Float32Array? = null;
    texcoords: Float32Array? = null;
    colors: Float32Array? = null;
    attributes: Array<DracoAttribute> = new Array<DracoAttribute>();

    attributeById(uniqueId: u32): DracoAttribute? {
        for (let i = 0; i < this.attributes.length; i++) {
            let att = this.attributes[i];
            if (att.uniqueId == uniqueId) {
                return att;
            }
        }
        return null;
    }
}

function extract(
    mesh: Mesh, out: DracoMesh, type: i32, numPoints: i32): Float32Array? {
    let attId = mesh.getNamedAttributeId(type);
    if (attId < 0) {
        return null;
    }
    let raw = out.attributes[attId];
    if (raw.dataType == DataType.FLOAT32) {
        return Float32Array.wrap(raw.data);
    }
    return mesh.attribute(attId).extractToFloat32(numPoints);
}

// Decodes a Draco mesh bitstream (a .drc file's bytes, or the buffer from a
// glTF KHR_draco_mesh_compression bufferView).
export unsafe function decode(data: ArrayBuffer): DracoMesh {
    let out = new DracoMesh();

    let db = new DecoderBuffer();
    db.init(data);

    let decoder = new Decoder();
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

    // Faces hold point ids, 3 per corner; copy the exact decoded range.
    let faces = new Int32Array(numFaces * 3);
    memory.copy(faces.dataStart, mesh.faces.dataStart, <usize>faces.length << 2);
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
    out.positions = extract(mesh, out, GeometryAttributeType.POSITION, numPoints);
    out.normals = extract(mesh, out, GeometryAttributeType.NORMAL, numPoints);
    out.texcoords = extract(mesh, out, GeometryAttributeType.TEX_COORD, numPoints);
    out.colors = extract(mesh, out, GeometryAttributeType.COLOR, numPoints);

    out.ok = true;
    return out;
}
