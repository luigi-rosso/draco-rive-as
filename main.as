// DracoBench: checks each sample against its DracoPy golden fixture in init,
// then times draco.decode on the bundled models one model per frame and
// tracks wasm memory across repeated decodes, so the frame collector gets a
// boundary between them the way a loading scene would.

import { Layout, Context } from "rive/host";
import { decode, DracoMesh } from "./lib/draco";

declare function emscripten_get_now(): f64;

const EPS: f64 = 1e-4;

const BENCH_NAMES: Array<string> = [
    "icosphere", "sphere_10k", "sphere_40k", "bunny", "avocado", "barramundi",
    "boombox", "corset", "lantern", "waterbottle",
];
const BENCH_ITERS: Array<i32> = [50, 10, 3, 10, 50, 10, 10, 3, 10, 10];

const GOLDEN_NAMES: Array<string> = [
    "tetra", "cube", "icosphere", "texquad", "sphere_10k", "sphere_40k",
];

// Repeated decodes of one model, one per frame, to show whether memory
// settles once the collector runs between them.
const SOAK_NAME = "corset";
const SOAK_FRAMES = 30;

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

function pagesMB(): string {
    return fmtFixed(<f64>memory.size() * 65536.0 / 1048576.0, 1) + " MB";
}

export class Main extends Layout {
    context: Context? = null;
    step: i32 = 0;
    soakStartPages: i32 = 0;

    override init(context: Context): bool {
        this.context = context;
        for (let i = 0; i < GOLDEN_NAMES.length; i++) {
            let name = GOLDEN_NAMES[i];
            let drc = context.blob(name);
            let golden = context.blob(name + ".golden");
            if (drc == null || golden == null) {
                context.log("DRACO-GOLDEN: " + name + " FAIL missing blob");
            } else {
                let first = goldenLine(name, drc, golden);
                let second = goldenLine(name, drc, golden);
                context.log(first == second ? first : first + " FAIL repeat differs");
            }
        }
        context.log("DRACO-BENCH: start, heap " + pagesMB());
        return true;
    }

    override advance(seconds: f64): bool {
        let context = this.context;
        if (context == null) {
            return false;
        }
        let i = this.step++;
        if (i < BENCH_NAMES.length) {
            this.bench(context, BENCH_NAMES[i], BENCH_ITERS[i]);
            return true;
        }
        let s = i - BENCH_NAMES.length;
        if (s <= SOAK_FRAMES) {
            this.soak(context, s);
            return true;
        }
        if (s == SOAK_FRAMES + 1) {
            this.burst(context);
            return true;
        }
        return false;
    }

    private bench(context: Context, name: string, iters: i32): void {
        let blob = context.blob(name);
        if (blob == null) {
            context.log("DRACO-BENCH: missing " + name);
            return;
        }
        let t0 = emscripten_get_now();
        let m: DracoMesh = decode(blob);
        let firstMs = emscripten_get_now() - t0;
        t0 = emscripten_get_now();
        for (let it = 0; it < iters; it++) {
            m = decode(blob);
        }
        let perMs = (emscripten_get_now() - t0) / <f64>iters;
        let mbps: f64 = perMs > 0 ? <f64>blob.byteLength / 1048576.0 / (perMs / 1000.0) : 0;
        context.log(
            "DRACO-BENCH: " + name + " | " + m.numPoints.toString() + " verts " +
            m.numFaces.toString() + " tris | " + blob.byteLength.toString() +
            " B | first " + fmtFixed(firstMs, 3) + " ms | " + fmtFixed(perMs, 3) +
            " ms/decode | " + fmtFixed(mbps, 2) + " MB/s | heap " + pagesMB() +
            (m.ok ? "" : " | FAIL " + m.error));
    }

    private soak(context: Context, frame: i32): void {
        let blob = context.blob(SOAK_NAME);
        if (blob == null) {
            return;
        }
        if (frame == 0) {
            this.soakStartPages = memory.size();
        }
        decode(blob);
        if (frame == SOAK_FRAMES) {
            context.log(
                "DRACO-SOAK: " + SOAK_NAME + " one decode per frame x" +
                SOAK_FRAMES.toString() + " | heap " +
                fmtFixed(<f64>this.soakStartPages * 65536.0 / 1048576.0, 1) +
                " MB -> " + pagesMB());
        }
    }

    private burst(context: Context): void {
        let blob = context.blob(SOAK_NAME);
        if (blob == null) {
            return;
        }
        let before = pagesMB();
        for (let i = 0; i < SOAK_FRAMES; i++) {
            decode(blob);
        }
        context.log(
            "DRACO-SOAK: " + SOAK_NAME + " x" + SOAK_FRAMES.toString() +
            " in one frame | heap " + before + " -> " + pagesMB());
        context.log("DRACO-BENCH: done");
    }
}
