// Phase C golden gate: compiles the full AS decoder with rasc, decodes each
// sample .drc in node, and diffs against the DracoPy reference fixtures
// (assets/*.golden.bin from scripts/make_golden.py). Indices must match
// exactly; float attributes to EPS, with actual max-abs-diffs reported.

import { execFileSync } from 'child_process';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { homedir } from 'os';

const HERE = dirname(fileURLToPath(import.meta.url));
const RASC = process.env.RASC ??
    join(homedir(), 'Projects/rive/packages/rasc/animascript/out/release/rasc');
const AS_STD = process.env.AS_STD ??
    join(homedir(), 'Projects/rive/packages/rasc/animascript/std');
const WASM = join(HERE, 'dracoC.wasm');

execFileSync(RASC, [
    join(HERE, '..', '_verifyC.as'),
    '--path', AS_STD,
    '--lib', join(AS_STD, 'assembly'),
    '--runtime', 'stub',
    '-o', WASM,
], { stdio: 'inherit' });

const wasmBytes = readFileSync(WASM);
const EPS = 1e-4;
const MESHES = ['tetra', 'cube', 'icosphere', 'texquad', 'sphere_10k', 'sphere_40k'];

let failures = 0;

function maxAbsDiff(got, want) {
    let maxErr = 0;
    for (let i = 0; i < want.length; i++) {
        const d = Math.abs(got[i] - want[i]);
        if (d > maxErr) maxErr = d;
    }
    return maxErr;
}

// One warm instance for every decode, each mesh decoded twice: exercises the
// cAlloc heap rewind the bench lanes rely on.
const { instance } = await WebAssembly.instantiate(
    wasmBytes, new Proxy({}, { get: () => new Proxy({}, { get: () => () => 0 }) }));

for (const baseName of MESHES.flatMap(n => [n, n + ' (repeat)'])) {
    const name = baseName.replace(' (repeat)', '');
    const drc = readFileSync(join(HERE, '..', 'assets', `${name}.drc`));
    const golden = readFileSync(join(HERE, '..', 'assets', `${name}.golden.bin`));

    const e = instance.exports;

    const ptr = e.cAlloc(drc.length);
    new Uint8Array(e.memory.buffer, ptr, drc.length).set(drc);
    const ok = e.cDecode();
    if (!ok) {
        const err = Buffer.from(
            e.memory.buffer, e.cErrorPtr(), e.cErrorLen() * 2).toString('utf16le');
        console.log(`${baseName}: FAIL decode error: ${err}`);
        failures++;
        continue;
    }

    const gNumPoints = golden.readUInt32LE(0);
    const gNumFaces = golden.readUInt32LE(4);
    const gFlags = golden.readUInt32LE(8);
    const posOff = 12;
    const idxOff = posOff + gNumPoints * 12;

    const problems = [];
    const numPoints = e.cNumPoints();
    const numFaces = e.cNumFaces();
    if (numPoints !== gNumPoints) problems.push(`numPoints ${numPoints} != ${gNumPoints}`);
    if (numFaces !== gNumFaces) problems.push(`numFaces ${numFaces} != ${gNumFaces}`);

    const diffs = [];
    if (problems.length === 0) {
        // Indices: exact.
        const faces = new Int32Array(e.memory.buffer, e.cFacesPtr(), gNumFaces * 3);
        const gFaces = new Uint32Array(golden.buffer, golden.byteOffset + idxOff, gNumFaces * 3);
        for (let i = 0; i < gFaces.length; i++) {
            if ((faces[i] >>> 0) !== gFaces[i]) {
                problems.push(`index mismatch at ${i}: ${faces[i]} != ${gFaces[i]}`);
                break;
            }
        }

        const attrs = [['positions', e.cPositionsPtr(), 3, posOff]];
        let off = idxOff + gNumFaces * 12;
        if (gFlags & 1) {
            attrs.push(['normals', e.cNormalsPtr(), 3, off]);
            off += gNumPoints * 12;
        }
        if (gFlags & 2) {
            attrs.push(['texcoords', e.cTexcoordsPtr(), 2, off]);
        }
        for (const [attName, attPtr, comps, gOff] of attrs) {
            if (attPtr === 0) {
                problems.push(`${attName} missing from decode`);
                continue;
            }
            const got = new Float32Array(e.memory.buffer, attPtr, gNumPoints * comps);
            const want = new Float32Array(gNumPoints * comps);
            for (let i = 0; i < want.length; i++) {
                want[i] = golden.readFloatLE(gOff + i * 4);
            }
            const err = maxAbsDiff(got, want);
            diffs.push(`${attName}=${err.toExponential(3)}`);
            if (err > EPS) {
                problems.push(`${attName} max-abs-diff ${err} > ${EPS}`);
            }
        }
    }

    if (problems.length > 0) {
        console.log(`${baseName}: FAIL ${problems.join('; ')}`);
        failures++;
    } else {
        console.log(
            `${baseName}: OK ${gNumPoints} verts ${gNumFaces} tris | max-abs-diff ${diffs.join(' ')}`);
    }
}

console.log(failures === 0 ? 'golden gate: all six green (x2 warm)' : `golden gate: ${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
