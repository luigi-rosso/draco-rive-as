import { readFileSync } from 'fs';

const bytes = readFileSync('./verifyB.wasm');
const { instance } = await WebAssembly.instantiate(bytes, new Proxy({}, {get:()=>new Proxy({},{get:()=>()=>0})}));
const e = instance.exports;

let failures = 0, checks = 0;
function check(cond, msg) { checks++; if (!cond) { failures++; if (failures < 25) console.log('FAIL:', msg); } }

const meshDefs = {
    strip: [[0,1,2],[2,1,3],[2,3,4],[4,3,5],[4,5,6],[6,5,7]],
    tetra: [[0,1,2],[0,3,1],[0,2,3],[1,3,2]],
    fan: [[0,1,2],[0,2,3],[0,3,4]],
};

let current = null;
const lines = readFileSync('vectors/pred_vectors.txt', 'utf8').trim().split('\n');
for (const line of lines) {
    const parts = line.split(' ');
    const [tag, name] = parts;
    if (current !== name) {
        e.ctBegin();
        for (const f of meshDefs[name]) e.ctAddFace(f[0], f[1], f[2]);
        check(e.ctBuild() === 1, `ctBuild(${name})`);
        check(e.predSetup() > 0, `predSetup(${name})`);
        current = name;
    }
    if (tag === 'TEX') {
        const [d, ok, p0, p1] = parts.slice(2).map(Number);
        const gok = e.texCase(d);
        check(gok === ok, `${name} tex(${d}) ok got ${gok} want ${ok}`);
        check(e.texPredVal(0) === p0 && e.texPredVal(1) === p1,
            `${name} tex(${d}) pred got (${e.texPredVal(0)},${e.texPredVal(1)}) want (${p0},${p1})`);
    } else if (tag === 'GN') {
        const [d, p0, p1, p2] = parts.slice(2).map(Number);
        e.gnCase(d);
        check(e.gnPredVal(0) === p0 && e.gnPredVal(1) === p1 && e.gnPredVal(2) === p2,
            `${name} gn(${d}) got (${e.gnPredVal(0)},${e.gnPredVal(1)},${e.gnPredVal(2)}) want (${p0},${p1},${p2})`);
    }
}

console.log(`checks: ${checks}, failures: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
