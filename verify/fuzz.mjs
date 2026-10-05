// Robustness gate: feeds deterministic corruptions of the repo assets
// (truncations, header counts set to huge values, byte flips, overwrites)
// plus the known repro cases to the AS decoder. Every case must decode or
// return ok=false; a trap or wasm memory past MAX_MB fails the run.
// WASM picks the driver build (default dracoC.wasm from golden.mjs).

import { readFileSync, readdirSync } from 'fs';
import { dirname, join, basename } from 'path';
import { fileURLToPath } from 'url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ASSETS = join(HERE, '..', 'assets');
const WASM = process.env.WASM ?? join(HERE, 'dracoC.wasm');
const MAX_MB = +(process.env.MAX_MB ?? 256);
const MAX_SEED_BYTES = 80000;

const HUGE = [0xFFFFFFFF, 0x7FFFFFFF, 0x55555555, 0x40000000, 0x10000000, 0x01000000,
    0x00200000, 0x0001FFFF, 0x10000, 0xFFFF, 0x100, 0xFF, 0];

function rng(seed) {
    let s = seed >>> 0 || 1;
    return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

function varint(v) {
    const out = [];
    v = BigInt(v);
    do { let b = Number(v & 0x7fn); v >>= 7n; if (v) b |= 0x80; out.push(b); } while (v);
    return out;
}

function varintEnd(buf, off) {
    while (off < buf.length && (buf[off++] & 0x80)) {}
    return off;
}

// Byte spans of the connectivity header counts, for targeted corruption.
function headerFields(buf) {
    const spans = [];
    if (buf.length < 12 || (buf[10] & 0x80)) {
        return spans;
    }
    // Sequential: num_faces, num_points. Edgebreaker: a traversal byte,
    // num_encoded_vertices, num_faces, an attribute data byte, then the
    // symbol and split symbol counts.
    const edgebreaker = buf[8] !== 0;
    let off = edgebreaker ? 12 : 11;
    for (let i = 0; i < (edgebreaker ? 4 : 2); i++) {
        if (edgebreaker && i === 2) {
            off++;
        }
        const end = varintEnd(buf, off);
        spans.push([off, end]);
        off = end;
    }
    return spans;
}

function* mutations(buf, seedIndex) {
    const n = buf.length;
    for (let i = 0; i < 64; i++) {
        const at = Math.floor(i * n / 64);
        yield [buf.subarray(0, at), `trunc@${at}`];
    }
    for (const [s, e] of headerFields(buf)) {
        for (const v of HUGE) {
            yield [Buffer.concat([buf.subarray(0, s), Buffer.from(varint(v)), buf.subarray(e)]), `count@${s}=${v.toString(16)}`];
        }
    }
    const r = rng(seedIndex * 104729 + 17);
    for (let i = 0; i < 150; i++) {
        const out = Buffer.from(buf);
        const desc = [];
        for (let k = 1 + Math.floor(r() * 3); k > 0; k--) {
            const at = 11 + Math.floor(r() * (n - 11));
            out[at] = Math.floor(r() * 256);
            desc.push(at);
        }
        yield [out, `flip@${desc.join(',')}`];
    }
    for (let i = 0; i < 100; i++) {
        const at = 11 + Math.floor(r() * Math.min(n - 11, 400));
        const v = HUGE[Math.floor(r() * 9)];
        const enc = r() < 0.5 ? varint(v) : [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, v >>> 24];
        const out = Buffer.from(buf);
        enc.forEach((b, j) => { if (at + j < n) out[at + j] = b; });
        yield [out, `over@${at}=${v.toString(16)}`];
    }
}

function patch(name, edits) {
    const out = Buffer.from(readFileSync(join(ASSETS, name + '.drc')));
    for (const [at, bytes] of edits) {
        bytes.forEach((b, j) => { out[at + j] = b; });
    }
    return out;
}

function splice(name, at, len, bytes) {
    const buf = readFileSync(join(ASSETS, name + '.drc'));
    return Buffer.concat([buf.subarray(0, at), Buffer.from(bytes), buf.subarray(at + len)]);
}

// Review repros: [description, bytes, expect] where expect is 'fail' or 'any'.
const REPROS = [
    ['sequential num_points 0x10000000', splice('seq_ico_compressed', 13, 2, varint(0x10000000)), 'fail'],
    ['sequential num_points 0x01000000', splice('seq_ico_compressed', 13, 2, varint(0x01000000)), 'fail'],
    ['tex coord orientations count', patch('cube_att_cl10', [[137, [0x32]], [181, [0x12]]]), 'any'],
    ['rans state with too few bytes', patch('tetra', [[45, varint(0xFFFFFFFF)]]), 'fail'],
    ['overlong varint index', patch('seq_sparse_varint', [[191, [0x80, 0x80, 0x80, 0x80, 0x01]]]), 'fail'],
];

const imports = new Proxy({}, { get: () => new Proxy({}, { get: () => () => 0 }) });
const module = new WebAssembly.Module(readFileSync(WASM));
let e = new WebAssembly.Instance(module, imports).exports;
let highWaterMB = 0;

// 'ok', 'fail', or a failure description.
function run(input) {
    try {
        const ptr = e.cAlloc(input.length);
        new Uint8Array(e.memory.buffer, ptr, input.length).set(input);
        const ok = e.cDecode();
        const mb = e.memory.buffer.byteLength / 1048576;
        highWaterMB = Math.max(highWaterMB, mb);
        if (mb > MAX_MB) {
            e = new WebAssembly.Instance(module, imports).exports;
            return `memory ${mb} MB`;
        }
        return ok ? 'ok' : 'fail';
    } catch (x) {
        e = new WebAssembly.Instance(module, imports).exports;
        return `trap ${x.message}`;
    }
}

let cases = 0;
let failures = 0;
const counts = { ok: 0, fail: 0 };
function check(name, input, expect) {
    cases++;
    const got = run(input);
    if (got === 'ok' || got === 'fail') {
        counts[got]++;
        if (expect === 'fail' && got !== 'fail') {
            failures++;
            console.log(`FAIL ${name}: decoded but must be rejected`);
        }
        return;
    }
    failures++;
    if (failures <= 30) {
        console.log(`FAIL ${name}: ${got}`);
    }
}

for (const [desc, bytes, expect] of REPROS) {
    check(`repro ${desc}`, bytes, expect);
}
const seeds = readdirSync(ASSETS).filter(f => f.endsWith('.drc')).sort()
    .filter(f => readFileSync(join(ASSETS, f)).length <= MAX_SEED_BYTES);
seeds.forEach((file, si) => {
    const buf = readFileSync(join(ASSETS, file));
    for (const [input, desc] of mutations(buf, si)) {
        check(`${basename(file, '.drc')} ${desc}`, input, 'any');
    }
});

console.log(`fuzz: ${cases} cases over ${seeds.length} seeds, ${counts.ok} decoded, ${counts.fail} rejected, ` +
    `${failures} failures, memory high-water ${highWaterMB} MB (limit ${MAX_MB})`);
process.exit(failures === 0 ? 0 : 1);
