// Public facade for the Draco mesh decoder, mirroring the Luau draco.luau:
// decodes a Draco bitstream into flat typed-array attributes plus a flat face
// index array, all in decoded-point order. Errors surface on the result's
// ok/error fields (the stub runtime cannot throw recoverably).

import { DecoderBuffer } from "./core/DecoderBuffer";
import { GeometryAttributeType } from "./attributes/GeometryAttribute";
import { PointAttribute } from "./attributes/PointAttribute";
import { Decoder } from "./Decode";

// Decoded mesh: each attribute is a flat typed array of numPoints *
// components, indexed by faces (numFaces * 3).
export class DracoMesh {
    ok: bool = false;
    error: string = "";
    numPoints: i32 = 0;
    numFaces: i32 = 0;
    faces: Int32Array = new Int32Array(0);
    positions: Float32Array | null = null;
    normals: Float32Array | null = null;
    texcoords: Float32Array | null = null;
    colors: Float32Array | null = null;
}

function extract(att: PointAttribute | null, numPoints: i32): Float32Array | null {
    if (att == null) {
        return null;
    }
    return att.extractToFloat32(numPoints);
}

// Decodes a Draco mesh bitstream (a .drc file's bytes, or the buffer from a
// glTF KHR_draco_mesh_compression bufferView).
export function decode(data: ArrayBuffer): DracoMesh {
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

    out.positions = extract(
        mesh.getNamedAttribute(GeometryAttributeType.POSITION), numPoints);
    out.normals = extract(
        mesh.getNamedAttribute(GeometryAttributeType.NORMAL), numPoints);
    out.texcoords = extract(
        mesh.getNamedAttribute(GeometryAttributeType.TEX_COORD), numPoints);
    out.colors = extract(
        mesh.getNamedAttribute(GeometryAttributeType.COLOR), numPoints);

    out.ok = true;
    return out;
}
