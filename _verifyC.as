// Phase C node verification driver: exports a decode surface the golden
// harness (verify/golden.mjs) drives over raw wasm memory. cAlloc returns a
// buffer the harness fills with the .drc bytes; cDecode runs the full decoder;
// the pointer accessors expose the decoded arrays (0 = attribute absent).

import { decode, DracoMesh } from "./lib/draco";

let inputBuf: ArrayBuffer = new ArrayBuffer(0);
let result: DracoMesh = new DracoMesh();
let heapMark: usize = 0;

// Rewinds the bump allocator between decodes so a warm instance reuses its
// heap; prior results become invalid at the next cAlloc.
export function cAlloc(size: i32): usize {
    if (heapMark == 0) {
        heapMark = __mark();
    } else {
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
export function cErrorPtr(): usize {
    return changetype<usize>(result.error);
}

export function cErrorLen(): i32 {
    return result.error.length;
}
