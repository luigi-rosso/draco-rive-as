// DracoBench: times draco.decode on the bundled models and prints the same
// sentinel block the Luau DracoBench.luau emits, plus a DRACO-GOLDEN line per
// sample from the in-bake comparison against the DracoPy reference fixtures.

import { Protocol, Context } from "rive/host";
import { decode, DracoMesh } from "./lib/draco";

declare function emscripten_get_now(): f64;

const EPS: f64 = 1e-4;

// { name, iterations }
const BENCH_NAMES: Array<string> = ["icosphere", "sphere_10k", "sphere_40k", "bunny"];
const BENCH_ITERS: Array<i32> = [50, 10, 3, 50];

const GOLDEN_NAMES: Array<string> = [
    "tetra", "cube", "icosphere", "texquad", "sphere_10k", "sphere_40k",
];

// "%.<digits>f" fixed-point formatting (context.log has no printf).
function fmtFixed(x: f64, digits: i32): string {
    let scale: f64 = 1;
    for (let i = 0; i < digits; i++) {
        scale *= 10;
    }
    let scaled = <i64>Math.round(x * scale);
    let neg = scaled < 0;
    if (neg) {
        scaled = -scaled;
    }
    let whole = scaled / <i64>scale;
    let out = (neg ? "-" : "") + whole.toString();
    if (digits > 0) {
        let frac = (scaled % <i64>scale).toString();
        while (frac.length < digits) {
            frac = "0" + frac;
        }
        out += "." + frac;
    }
    return out;
}

// Max abs diff between a decoded f32 array and count floats at byteOff in the
// golden fixture; -1 when the decoded attribute is missing.
function attrMaxDiff(arr: Float32Array?, golden: ArrayBuffer, byteOff: i32, count: i32): f64 {
    if (arr == null || arr.length < count) {
        return -1;
    }
    let want = Float32Array.wrap(golden, byteOff, count);
    let maxErr: f64 = 0;
    for (let i = 0; i < count; i++) {
        let d = Math.abs(<f64>arr[i] - <f64>want[i]);
        if (d > maxErr) {
            maxErr = d;
        }
    }
    return maxErr;
}

// Returns the DRACO-GOLDEN line for one sample.
function goldenLine(name: string, drc: ArrayBuffer, golden: ArrayBuffer): string {
    let m = decode(drc);
    if (!m.ok) {
        return "DRACO-GOLDEN: " + name + " FAIL decode: " + m.error;
    }

    let header = Uint32Array.wrap(golden, 0, 3);
    let gNumPoints = <i32>header[0];
    let gNumFaces = <i32>header[1];
    let gFlags = <i32>header[2];
    if (m.numPoints != gNumPoints || m.numFaces != gNumFaces) {
        return "DRACO-GOLDEN: " + name + " FAIL counts " +
            m.numPoints.toString() + "/" + m.numFaces.toString() + " want " +
            gNumPoints.toString() + "/" + gNumFaces.toString();
    }

    let posOff = 12;
    let idxOff = posOff + gNumPoints * 12;

    // Indices: exact.
    let gFaces = Uint32Array.wrap(golden, idxOff, gNumFaces * 3);
    for (let i = 0; i < gNumFaces * 3; i++) {
        if (<u32>m.faces[i] != gFaces[i]) {
            return "DRACO-GOLDEN: " + name + " FAIL index mismatch at " + i.toString();
        }
    }

    let maxDiff = attrMaxDiff(m.positions, golden, posOff, gNumPoints * 3);
    if (maxDiff < 0) {
        return "DRACO-GOLDEN: " + name + " FAIL positions missing";
    }

    let off = idxOff + gNumFaces * 12;
    if ((gFlags & 1) != 0) {
        let d = attrMaxDiff(m.normals, golden, off, gNumPoints * 3);
        if (d < 0) {
            return "DRACO-GOLDEN: " + name + " FAIL normals missing";
        }
        if (d > maxDiff) {
            maxDiff = d;
        }
        off += gNumPoints * 12;
    }
    if ((gFlags & 2) != 0) {
        let d = attrMaxDiff(m.texcoords, golden, off, gNumPoints * 2);
        if (d < 0) {
            return "DRACO-GOLDEN: " + name + " FAIL texcoords missing";
        }
        if (d > maxDiff) {
            maxDiff = d;
        }
    }

    let verdict = maxDiff <= EPS ? " OK" : " FAIL";
    return "DRACO-GOLDEN: " + name + verdict + " maxdiff=" + maxDiff.toString();
}

class Main extends Protocol {
    ran: bool = false;

    implementsInit(): bool {
        return true;
    }

    init(context: Context): bool {
        if (this.ran) {
            return true;
        }
        this.ran = true;

        for (let i = 0; i < GOLDEN_NAMES.length; i++) {
            let name = GOLDEN_NAMES[i];
            let drc = context.blob(name);
            let golden = context.blob(name + ".golden");
            if (drc == null || golden == null) {
                context.log("DRACO-GOLDEN: " + name + " FAIL missing blob");
            } else {
                // Second decode runs on a rewound heap; both passes must
                // agree or the warm arena corrupted state.
                let first = goldenLine(name, drc, golden);
                let mark = __mark();
                let second = goldenLine(name, drc, golden);
                let same = first == second;
                __resetTo(mark);
                context.log(same ? first : first + " FAIL warm repeat differs");
            }
        }

        context.log("DRACO-BENCH: start");
        for (let i = 0; i < BENCH_NAMES.length; i++) {
            let name = BENCH_NAMES[i];
            let iters = BENCH_ITERS[i];
            let blob = context.blob(name);
            if (blob == null) {
                context.log("DRACO-BENCH: missing " + name);
                continue;
            }
            // Warm-up (parse + allocate) outside the timed loop; the timed
            // decodes reuse the warm-up's heap region via mark/reset.
            let mark = __mark();
            let m: DracoMesh = decode(blob);
            let t0 = emscripten_get_now();
            for (let it = 0; it < iters; it++) {
                __resetTo(mark);
                m = decode(blob);
            }
            let totalMs = emscripten_get_now() - t0;
            let perMs = totalMs / <f64>iters;
            let vertsPerSec: f64 = perMs > 0 ? <f64>m.numPoints / (perMs / 1000.0) : 0;
            context.log(
                "DRACO-BENCH: " + name + " | " + m.numPoints.toString() + " verts " +
                m.numFaces.toString() + " tris | " + fmtFixed(perMs, 3) +
                " ms/decode | " + fmtFixed(vertsPerSec, 0) + " verts/s | " +
                blob.byteLength.toString() + " B compressed | " + iters.toString() +
                " iters");
        }
        context.log("DRACO-BENCH: done");
        return true;
    }
}

export function generator(): Protocol {
    return new Main();
}
