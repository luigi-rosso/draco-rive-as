import { readFileSync } from 'fs';

const bytes = readFileSync('./verifyB.wasm');
const { instance } = await WebAssembly.instantiate(bytes, new Proxy({}, {get:()=>new Proxy({},{get:()=>()=>0})}));
const e = instance.exports;

let failures = 0, checks = 0;
function check(cond, msg) { checks++; if (!cond) { failures++; if (failures < 25) console.log('FAIL:', msg); } }

const meshDefs = {
    quad: [[0,1,2],[2,1,3]],
    tetra: [[0,1,2],[0,3,1],[0,2,3],[1,3,2]],
    fan: [[0,1,2],[0,2,3],[0,3,4]],
    strip: [[0,1,2],[2,1,3],[2,3,4],[4,3,5],[4,5,6],[6,5,7]],
};

function buildCt(name) {
    e.ctBegin();
    for (const f of meshDefs[name]) e.ctAddFace(f[0], f[1], f[2]);
    check(e.ctBuild() === 1, `ctBuild(${name})`);
}

const lines = readFileSync('vectors/trav_vectors.txt', 'utf8').trim().split('\n');
let current = null;
for (const line of lines) {
    const parts = line.split(' ');
    if (parts[0] === 'TRAV') {
        const name = parts[1], tname = parts[2];
        if (current !== name) { buildCt(name); current = name; }
        const n = Number(parts[3]);
        const got = e.travRun(tname === 'mpd' ? 1 : 0);
        check(got === n, `${name} ${tname} numPoints got ${got} want ${n}`);
        const pairs = parts.slice(4, 4 + n).map(x => x.split(':').map(Number));
        for (let i = 0; i < n; i++) {
            check(e.travPoint(i) === pairs[i][0], `${name} ${tname} point[${i}] got ${e.travPoint(i)} want ${pairs[i][0]}`);
            check(e.travCorner(i) === pairs[i][1], `${name} ${tname} corner[${i}] got ${e.travCorner(i)} want ${pairs[i][1]}`);
        }
        const v2v = parts.slice(4 + n).map(x => Number(x.slice(1)));
        for (let v = 0; v < v2v.length; v++) {
            check(e.travVertexToValue(v) === v2v[v], `${name} ${tname} v2v[${v}] got ${e.travVertexToValue(v)} want ${v2v[v]}`);
        }
    } else if (parts[0] === 'MACT') {
        let name = parts[1];
        const seams = name.endsWith('_seams');
        const base = seams ? name.slice(0, -6) : name;
        if (current !== base) { buildCt(base); current = base; }
        const nv = Number(parts[2]);
        const numCorners = meshDefs[base].length * 3;
        e.mactBegin();
        if (seams) {
            for (let c = 0; c < numCorners; c++) {
                const o = e.ctOpposite(c);
                if (o !== -1 && c < o && c % 2 === 0) e.mactAddSeam(c);
            }
        }
        const got = e.mactBuild();
        check(got === nv, `${name} numVertices got ${got} want ${nv}`);
        let idx = 3;
        for (let c = 0; c < numCorners; c++, idx++) {
            check(e.mactVertex(c) === Number(parts[idx]), `${name} vertex(${c}) got ${e.mactVertex(c)} want ${parts[idx]}`);
        }
        for (let v = 0; v < nv; v++, idx++) {
            const [lmc, onb, par] = parts[idx].slice(1).split(':').map(Number);
            check(e.mactLeftMost(v) === lmc, `${name} leftMost(${v}) got ${e.mactLeftMost(v)} want ${lmc}`);
            check(e.mactIsOnBoundary(v) === onb, `${name} isOnBoundary(${v}) got ${e.mactIsOnBoundary(v)} want ${onb}`);
            check(e.mactVertexParent(v) === par, `${name} vertexParent(${v}) got ${e.mactVertexParent(v)} want ${par}`);
        }
        for (let c = 0; c < numCorners; c++, idx++) {
            const o = Number(parts[idx].slice(1));
            check(e.mactOpposite(c) === o, `${name} opposite(${c}) got ${e.mactOpposite(c)} want ${o}`);
        }
    }
}

console.log(`checks: ${checks}, failures: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
