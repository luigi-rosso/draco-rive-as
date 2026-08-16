import { readFileSync } from 'fs';

const bytes = readFileSync('./verifyB.wasm');
const { instance } = await WebAssembly.instantiate(bytes, new Proxy({}, {get:()=>new Proxy({},{get:()=>()=>0})}));
const e = instance.exports;

let failures = 0, checks = 0;
function check(cond, msg) { checks++; if (!cond) { failures++; if (failures < 20) console.log('FAIL:', msg); } }

// 1. Luau-derived vectors (compiled into wasm).
const luauFails = e.runLuauVectors();
checks += 14;
if (luauFails !== 0) { failures += luauFails; console.log('FAIL: runLuauVectors ->', luauFails); }

// 2. Octahedron canonicalized transform sweep vs C++.
const octaLines = readFileSync('vectors/octa_vectors.txt', 'utf8').trim().split('\n');
let currentQb = -1;
for (const line of octaLines) {
    const parts = line.split(' ');
    if (parts[0] === 'TB') continue;
    const [qb, px, py, cx, cy, o0, o1] = parts.map(Number);
    if (qb !== currentQb) { check(e.octaSetup(qb) === 1, `octaSetup(${qb})`); currentQb = qb; }
    const packed = e.octaCase(px, py, cx, cy);
    const g0 = Number(BigInt.asIntN(32, packed >> 32n));
    const g1 = Number(BigInt.asIntN(32, packed & 0xFFFFFFFFn));
    check(g0 === o0 && g1 === o1, `octa qb=${qb} pred=(${px},${py}) corr=(${cx},${cy}) got (${g0},${g1}) want (${o0},${o1})`);
}

// 3. Toolbox diamond/modmax sweep (qb=4) vs C++.
check(e.tbSetup(4) === 1, 'tbSetup(4)');
for (const line of octaLines) {
    const parts = line.split(' ');
    if (parts[0] !== 'TB') continue;
    const [, s, t, ind, ds, dt, mm] = parts.map((x, i) => i === 0 ? x : Number(x));
    check(e.tbIsInDiamond(s, t) === ind, `tbIsInDiamond(${s},${t})`);
    check(e.tbInvertS(s, t) === ds && e.tbInvertT(s, t) === dt, `tbInvert(${s},${t}) got (${e.tbInvertS(s,t)},${e.tbInvertT(s,t)}) want (${ds},${dt})`);
    check(e.tbModMax(s + t) === mm, `tbModMax(${s + t})`);
}

// 4. Corner table + parallelogram sweeps vs C++.
const meshLines = readFileSync('vectors/mesh_vectors.txt', 'utf8').trim().split('\n');
const meshDefs = {
    quad: [[0,1,2],[2,1,3]],
    tetra: [[0,1,2],[0,3,1],[0,2,3],[1,3,2]],
    fan: [[0,1,2],[0,2,3],[0,3,4],[5,5,4]],
    bowtie: [[0,1,2],[0,3,4]],
};
let built = null;
for (const line of meshLines) {
    const parts = line.split(' ');
    const tag = parts[0];
    if (tag === 'CT') {
        const name = parts[1];
        const [nv, nc, ndeg, niso, nnew] = parts.slice(2).map(Number);
        e.ctBegin();
        for (const f of meshDefs[name]) e.ctAddFace(f[0], f[1], f[2]);
        check(e.ctBuild() === 1, `ctBuild(${name})`);
        built = name;
        check(e.ctNumVertices() === nv, `${name} numVertices got ${e.ctNumVertices()} want ${nv}`);
        check(e.ctNumCorners() === nc, `${name} numCorners`);
        check(e.ctNumDegenerated() === ndeg, `${name} numDegenerated`);
        check(e.ctNumIsolated() === niso, `${name} numIsolated got ${e.ctNumIsolated()} want ${niso}`);
        check(e.ctNumNew() === nnew, `${name} numNew got ${e.ctNumNew()} want ${nnew}`);
        e.ppSetup();
    } else if (tag === 'CTC') {
        const [name, c, opp, vert] = [parts[1], ...parts.slice(2).map(Number)];
        check(e.ctOpposite(c) === opp, `${name} opposite(${c}) got ${e.ctOpposite(c)} want ${opp}`);
        check(e.ctVertex(c) === vert, `${name} vertex(${c}) got ${e.ctVertex(c)} want ${vert}`);
    } else if (tag === 'CTV') {
        const [name, v, lmc, onb, val] = [parts[1], ...parts.slice(2).map(Number)];
        check(e.ctLeftMost(v) === lmc, `${name} leftMost(${v}) got ${e.ctLeftMost(v)} want ${lmc}`);
        check(e.ctIsOnBoundary(v) === onb, `${name} isOnBoundary(${v})`);
        check(e.ctValence(v) === val, `${name} valence(${v}) got ${e.ctValence(v)} want ${val}`);
    } else if (tag === 'PP') {
        const [name, c, ok, p0, p1, p2] = [parts[1], ...parts.slice(2).map(Number)];
        const gok = e.ppCase(c);
        check(gok === ok, `${name} pp(${c}) ok got ${gok} want ${ok}`);
        if (ok === 1) {
            check(e.ppPred(0) === p0 && e.ppPred(1) === p1 && e.ppPred(2) === p2,
                `${name} pp(${c}) pred got (${e.ppPred(0)},${e.ppPred(1)},${e.ppPred(2)}) want (${p0},${p1},${p2})`);
        }
    }
}

// 5. Canonicalize + quantized octahedral coords sweep (qb=8) vs C++.
check(e.tbSetup(8) === 1, 'tbSetup(8)');
for (const line of meshLines) {
    const parts = line.split(' ');
    if (parts[0] !== 'CANON') continue;
    const [x, y, z, vx, vy, vz, s, t] = parts.slice(1).map(Number);
    e.canonCase(x, y, z);
    const got = [e.canonGet(0), e.canonGet(1), e.canonGet(2), e.canonGet(3), e.canonGet(4)];
    check(got[0] === vx && got[1] === vy && got[2] === vz && got[3] === s && got[4] === t,
        `canon(${x},${y},${z}) got ${got} want (${vx},${vy},${vz},${s},${t})`);
}

console.log(`checks: ${checks}, failures: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
