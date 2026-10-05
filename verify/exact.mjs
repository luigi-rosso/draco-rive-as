// Byte-exact gate: decodes each .drc with the AS decoder (WASM, default
// dracoC.wasm from golden.mjs) and with canonical draco (cppref/dump), then
// requires the faces and every attribute's raw values to match exactly, or
// both decoders to reject the file. Extra .drc directories come from
// DRACO_EXTRA (colon separated).

import { spawnSync } from 'child_process';
import { readFileSync, readdirSync, mkdirSync } from 'fs';
import { dirname, join, basename } from 'path';
import { fileURLToPath } from 'url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'vectors', 'exact');
mkdirSync(OUT, { recursive: true });

const dirs = [join(HERE, '..', 'assets'), ...(process.env.DRACO_EXTRA ?? '').split(':').filter(Boolean)];
const files = dirs.flatMap(d => readdirSync(d).filter(f => f.endsWith('.drc')).sort().map(f => join(d, f)));

const { instance } = await WebAssembly.instantiate(
    readFileSync(process.env.WASM ?? join(HERE, 'dracoC.wasm')),
    new Proxy({}, { get: () => new Proxy({}, { get: () => () => 0 }) }));
const e = instance.exports;

let failures = 0;
for (const file of files) {
    const name = basename(file, '.drc');
    const refPath = join(OUT, name + '.bin');
    const canon = spawnSync(join(HERE, 'cppref', 'dump'), [file, refPath], { encoding: 'utf8' });
    const drc = readFileSync(file);

    const ptr = e.cAlloc(drc.length);
    new Uint8Array(e.memory.buffer, ptr, drc.length).set(drc);
    const decoded = e.cDecode();
    const err = decoded ? '' : Buffer.from(e.memory.buffer, e.cErrorPtr(), e.cErrorLen() * 2).toString('utf16le');
    if (canon.status !== 0) {
        const canonErr = canon.stderr.trim().split(': ').pop();
        if (decoded) {
            console.log(`${name}: FAIL decoded but canonical draco rejects it: ${canonErr}`);
            failures++;
        } else {
            console.log(`${name}: OK both reject (${err} / ${canonErr})`);
        }
        continue;
    }
    const ref = readFileSync(refPath);
    if (!decoded) {
        console.log(`${name}: FAIL decode error: ${err}`);
        failures++;
        continue;
    }
    const mem = () => Buffer.from(e.memory.buffer);
    const problems = [];
    let off = 0;
    const u32 = () => { const v = ref.readUInt32LE(off); off += 4; return v; };
    const numPoints = u32(), numFaces = u32(), numAttrs = u32();
    if (e.cNumPoints() !== numPoints) problems.push(`numPoints ${e.cNumPoints()} != ${numPoints}`);
    if (e.cNumFaces() !== numFaces) problems.push(`numFaces ${e.cNumFaces()} != ${numFaces}`);
    if (e.cNumAttributes() !== numAttrs) problems.push(`numAttributes ${e.cNumAttributes()} != ${numAttrs}`);
    if (problems.length === 0) {
        const faceBytes = numFaces * 12;
        if (!mem().subarray(e.cFacesPtr(), e.cFacesPtr() + faceBytes).equals(ref.subarray(off, off + faceBytes))) {
            problems.push('faces differ');
        }
        off += faceBytes;
        const kinds = [];
        for (let i = 0; i < numAttrs; i++) {
            const [uid, type, dt, nc, norm, len] = [u32(), u32() | 0, u32(), u32(), u32(), u32()];
            const got = [e.cAttrUniqueId(i), e.cAttrType(i), e.cAttrDataType(i), e.cAttrNumComponents(i), e.cAttrNormalized(i), e.cAttrLen(i)];
            if (got.join() !== [uid, type, dt, nc, norm, len].join()) {
                problems.push(`attribute ${i} header ${got} != ${[uid, type, dt, nc, norm, len]}`);
            } else if (!mem().subarray(e.cAttrPtr(i), e.cAttrPtr(i) + len).equals(ref.subarray(off, off + len))) {
                problems.push(`attribute ${i} (type ${type}) values differ`);
            }
            kinds.push(`${type}:${nc}x${dt}`);
            off += len;
        }
        if (problems.length === 0) {
            console.log(`${name}: OK ${numPoints} points ${numFaces} faces attrs ${kinds.join(' ')}`);
            continue;
        }
    }
    console.log(`${name}: FAIL ${problems.join('; ')}`);
    failures++;
}
console.log(failures === 0 ? `exact gate: all ${files.length} byte-exact` : `exact gate: ${failures} of ${files.length} FAILED`);
process.exit(failures === 0 ? 0 : 1);
