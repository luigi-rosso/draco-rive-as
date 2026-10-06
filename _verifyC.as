// Phase C node verification driver: exports a decode surface the golden
// harness (verify/golden.mjs) drives over raw wasm memory. cAlloc returns a
// buffer the harness fills with the .drc bytes; cDecode runs the full decoder;
// the pointer accessors expose the decoded arrays (0 = attribute absent).

import { decode, DracoMesh } from "./lib/draco";

const emptyInput = new ArrayBuffer(0);
const emptyResult = new DracoMesh();
let inputBuf: ArrayBuffer = emptyInput;
let result: DracoMesh = emptyResult;
let heapMark: usize = 0;

// Rewinds the bump allocator between decodes so a warm instance reuses its
// heap; prior results become invalid at the next cAlloc.
export unsafe function cAlloc(size: i32): usize {
    if (heapMark == 0) {
        heapMark = __mark();
    } else {
        // Debug stub builds trap on statics left pointing past the mark.
        inputBuf = emptyInput;
        result = emptyResult;
        __resetTo(heapMark);
    }
    inputBuf = new ArrayBuffer(size);
    return changetype<usize>(inputBuf);
}

export function cDecode(): i32 {
    result = decode(inputBuf);
    return result.ok ? 1 : 0;
}

export function cNumPoints(): i32 {
    return result.numPoints;
}

export function cNumFaces(): i32 {
    return result.numFaces;
}

export function cFacesPtr(): usize {
    return result.faces.dataStart;
}

export function cPositionsPtr(): usize {
    let arr = result.positions;
    return arr == null ? 0 : arr.dataStart;
}

export function cNormalsPtr(): usize {
    let arr = result.normals;
    return arr == null ? 0 : arr.dataStart;
}

export function cTexcoordsPtr(): usize {
    let arr = result.texcoords;
    return arr == null ? 0 : arr.dataStart;
}

// UTF-16 code units at the string's data pointer.
export unsafe function cErrorPtr(): usize {
    return changetype<usize>(result.error);
}

export function cErrorLen(): i32 {
    return result.error.length;
}

export function cNumAttributes(): i32 {
    return result.attributes.length;
}

export function cAttrUniqueId(i: i32): u32 {
    return result.attributes[i].uniqueId;
}

export function cAttrType(i: i32): i32 {
    return result.attributes[i].attributeType;
}

export function cAttrDataType(i: i32): i32 {
    return result.attributes[i].dataType;
}

export function cAttrNumComponents(i: i32): i32 {
    return result.attributes[i].numComponents;
}

export function cAttrNormalized(i: i32): i32 {
    return result.attributes[i].normalized ? 1 : 0;
}

export unsafe function cAttrPtr(i: i32): usize {
    return changetype<usize>(result.attributes[i].data);
}

export function cAttrLen(i: i32): i32 {
    return result.attributes[i].data.byteLength;
}
