// Phase B verification entry (temporary, deleted after the report): exports
// drivers for the node harness to compare against Luau-derived vectors and
// C++ reference sweeps.

import { DecoderBuffer } from "./lib/core/DecoderBuffer";
import { OctahedronToolBox } from "./lib/attributes/NormalCompressionUtils";
import { PredictionSchemeWrapDecodingTransform } from "./lib/prediction/PredictionSchemeWrapDecodingTransform";
import { PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform } from "./lib/prediction/PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform";
import { PredictionSchemeDeltaDecoderWrap } from "./lib/prediction/PredictionSchemeDeltaDecoder";
import { computeParallelogramPrediction } from "./lib/prediction/MeshPredictionSchemeParallelogramDecoder";
import { intSqrt } from "./lib/prediction/MeshPredictionSchemeTexCoordsPortablePredictor";
import { CornerTable } from "./lib/mesh/CornerTable";
import { IntVector } from "./lib/mesh/IntVector";
import { Mesh } from "./lib/mesh/Mesh";

// ---- Wrap + delta vectors from tests/prediction_test.luau ----

function makeWrap(minV: i32, maxV: i32): PredictionSchemeWrapDecodingTransform {
    let bytes = new ArrayBuffer(8);
    store<i32>(changetype<usize>(bytes), minV);
    store<i32>(changetype<usize>(bytes) + 4, maxV);
    let db = new DecoderBuffer();
    db.init(bytes);
    let t = new PredictionSchemeWrapDecodingTransform();
    t.decodeTransformData(db);
    return t;
}

export function runLuauVectors(): i32 {
    let failures = 0;

    // WrapDecodingTransform: in-range addition.
    let t = makeWrap(-10, 10);
    t.init(1);
    let pred = new Int32Array(1);
    let corr = new Int32Array(1);
    let out = new Int32Array(1);
    pred[0] = 5;
    corr[0] = 3;
    t.computeOriginalValue(pred, 0, corr, 0, out, 0);
    if (out[0] != 8) failures++;

    // Wraps over max: 8 + 5 = 13 -> 13 - 21 = -8.
    pred[0] = 8;
    corr[0] = 5;
    t.computeOriginalValue(pred, 0, corr, 0, out, 0);
    if (out[0] != -8) failures++;

    // Wraps under min: -8 - 5 = -13 -> -13 + 21 = 8.
    pred[0] = -8;
    corr[0] = -5;
    t.computeOriginalValue(pred, 0, corr, 0, out, 0);
    if (out[0] != 8) failures++;

    // decodeTransformData reads min/max (checked via wrap behavior above).

    // DeltaDecoder cumulative reconstruction.
    let t2 = makeWrap(-100, 100);
    let d = new PredictionSchemeDeltaDecoderWrap(null, t2);
    let corr3 = new Int32Array(3);
    corr3[0] = 5;
    corr3[1] = 3;
    corr3[2] = -2;
    let out3 = new Int32Array(3);
    d.computeOriginalValues(corr3, out3, 3, 1, new Int32Array(0));
    if (out3[0] != 5) failures++;
    if (out3[1] != 8) failures++;
    if (out3[2] != 6) failures++;

    // Mesh faces (tests/geom_test.luau).
    let mesh = new Mesh();
    mesh.setNumFaces(2);
    mesh.setFace(0, 0, 1, 2);
    mesh.setFace(1, 2, 3, 0);
    if (mesh.numFaces() != 2) failures++;
    if (mesh.cornerToPointId(3) != 2) failures++;
    if (mesh.cornerToPointId(4) != 3) failures++;
    if (mesh.cornerToPointId(5) != 0) failures++;

    // intSqrt sanity against known values.
    if (intSqrt(0) != 0) failures++;
    if (intSqrt(1000000) != 1000) failures++;
    if (intSqrt(999999) != 999) failures++;
    if (intSqrt(u64.MAX_VALUE) != 4294967295) failures++;

    return failures;
}

// ---- Octahedron canonicalized decoding transform (C++ sweep) ----

let octaTransform = new PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform();

export function octaSetup(qb: i32): bool {
    let maxq = (1 << qb) - 1;
    let bytes = new ArrayBuffer(8);
    store<i32>(changetype<usize>(bytes), maxq);
    store<i32>(changetype<usize>(bytes) + 4, (maxq - 1) / 2);
    let db = new DecoderBuffer();
    db.init(bytes);
    octaTransform = new PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform();
    return octaTransform.decodeTransformData(db);
}

let octaPred = new Int32Array(2);
let octaCorr = new Int32Array(2);
let octaOut = new Int32Array(2);

export function octaCase(px: i32, py: i32, cx: i32, cy: i32): i64 {
    octaPred[0] = px;
    octaPred[1] = py;
    octaCorr[0] = cx;
    octaCorr[1] = cy;
    octaTransform.computeOriginalValue(octaPred, 0, octaCorr, 0, octaOut, 0);
    return (<i64>octaOut[0] << 32) | (<i64>octaOut[1] & 0xFFFFFFFF);
}

// ---- OctahedronToolBox helpers (C++ sweep) ----

let toolBox = new OctahedronToolBox();
let tbOut = new Int32Array(2);
let canonVec = new Int32Array(3);
let canonOut = new Int32Array(2);

export function tbSetup(qb: i32): bool {
    toolBox = new OctahedronToolBox();
    return toolBox.setQuantizationBits(qb);
}

export function tbIsInDiamond(s: i32, t: i32): i32 {
    return toolBox.isInDiamond(s, t) ? 1 : 0;
}

export function tbInvertS(s: i32, t: i32): i32 {
    toolBox.invertDiamond(s, t, tbOut);
    return tbOut[0];
}

export function tbInvertT(s: i32, t: i32): i32 {
    toolBox.invertDiamond(s, t, tbOut);
    return tbOut[1];
}

export function tbModMax(x: i32): i32 {
    return toolBox.modMax(x);
}

export function canonCase(x: i32, y: i32, z: i32): i32 {
    canonVec[0] = x;
    canonVec[1] = y;
    canonVec[2] = z;
    toolBox.canonicalizeIntegerVector(canonVec);
    toolBox.integerVectorToQuantizedOctahedralCoords(canonVec, canonOut);
    return 1;
}

export function canonGet(i: i32): i32 {
    if (i < 3) {
        return canonVec[i];
    }
    return canonOut[i - 3];
}

// ---- CornerTable + parallelogram (C++ sweep) ----

let ctFaces = new IntVector();
let ct = new CornerTable();

export function ctBegin(): void {
    ctFaces = new IntVector();
}

export function ctAddFace(a: i32, b: i32, c: i32): void {
    ctFaces.push(a);
    ctFaces.push(b);
    ctFaces.push(c);
}

export function ctBuild(): bool {
    ct = new CornerTable();
    return ct.init(ctFaces.view(), ctFaces.size() / 3);
}

export function ctNumVertices(): i32 {
    return ct.numVertices();
}

export function ctNumCorners(): i32 {
    return ct.numCorners();
}

export function ctNumDegenerated(): i32 {
    return ct.numDegeneratedFaces();
}

export function ctNumIsolated(): i32 {
    return ct.numIsolatedVertices();
}

export function ctNumNew(): i32 {
    return ct.numNewVertices();
}

export function ctOpposite(c: i32): i32 {
    return ct.opposite(c);
}

export function ctVertex(c: i32): i32 {
    return ct.vertex(c);
}

export function ctLeftMost(v: i32): i32 {
    return ct.leftMostCorner(v);
}

export function ctIsOnBoundary(v: i32): i32 {
    return ct.isOnBoundary(v) ? 1 : 0;
}

export function ctValence(v: i32): i32 {
    return ct.valence(v);
}

// Parallelogram sweep over the built table: identity vertex-to-data map plus
// LCG data identical to the C++ reference (seed 777).
let ppData = new Int32Array(0);
let ppMap = new Int32Array(0);
let ppPredVals = new Int32Array(3);

export function ppSetup(): void {
    let nv = ct.numVertices();
    ppMap = new Int32Array(nv);
    for (let v = 0; v < nv; v++) {
        ppMap[v] = v;
    }
    ppData = new Int32Array(nv * 3);
    let rng: u32 = 777;
    for (let i = 0; i < nv * 3; i++) {
        rng = rng * 1664525 + 1013904223;
        ppData[i] = <i32>(rng % 2001) - 1000;
    }
}

export function ppCase(c: i32): i32 {
    ppPredVals[0] = 0;
    ppPredVals[1] = 0;
    ppPredVals[2] = 0;
    return computeParallelogramPrediction(
        ct.numVertices(), c, ct, ppMap, ppData, 3, ppPredVals) ? 1 : 0;
}

export function ppPred(i: i32): i32 {
    return ppPredVals[i];
}

// ---- Traverser + sequencer differential drivers ----

import { MeshTraversalSequencer } from "./lib/mesh/MeshTraversalSequencer";
import { MeshAttributeIndicesEncodingData } from "./lib/mesh/MeshAttributeIndicesEncodingData";
import { MeshAttributeIndicesEncodingObserver } from "./lib/mesh/MeshAttributeIndicesEncodingObserver";
import { DepthFirstTraverser } from "./lib/mesh/DepthFirstTraverser";
import { MaxPredictionDegreeTraverser } from "./lib/mesh/MaxPredictionDegreeTraverser";
import { TraverserBase } from "./lib/mesh/TraverserBase";
import { MeshAttributeCornerTable } from "./lib/mesh/MeshAttributeCornerTable";

let travSequencer: MeshTraversalSequencer | null = null;
let travEncodingData = new MeshAttributeIndicesEncodingData();

// Runs a traversal over the built corner table with mesh faces equal to the
// corner table vertices (point id == vertex id). Returns the number of
// sequenced points, or -1 on failure.
export function travRun(useMpd: i32): i32 {
    let mesh = new Mesh();
    mesh.setNumFaces(ct.numFaces());
    for (let f = 0; f < ct.numFaces(); f++) {
        mesh.setFace(f, ct.vertex(3 * f), ct.vertex(3 * f + 1), ct.vertex(3 * f + 2));
    }
    mesh.setNumPoints(ct.numVertices());
    travEncodingData = new MeshAttributeIndicesEncodingData();
    travEncodingData.init(ct.numVertices());
    let sequencer = new MeshTraversalSequencer(mesh, travEncodingData);
    let observer = new MeshAttributeIndicesEncodingObserver(
        ct, mesh, sequencer, travEncodingData);
    let traverser: TraverserBase;
    if (useMpd != 0) {
        traverser = new MaxPredictionDegreeTraverser();
    } else {
        traverser = new DepthFirstTraverser();
    }
    traverser.init(ct, observer);
    sequencer.setTraverser(traverser);
    travSequencer = sequencer;
    if (!sequencer.generateSequence()) {
        return -1;
    }
    return sequencer.getOutputPointIds().length;
}

export function travPoint(i: i32): i32 {
    return travSequencer!.getOutputPointIds()[i];
}

export function travCorner(i: i32): i32 {
    return travEncodingData.encodedAttributeValueIndexToCornerMap.get(i);
}

export function travVertexToValue(v: i32): i32 {
    return travEncodingData.vertexToEncodedAttributeValueIndexMap[v];
}

// ---- MeshAttributeCornerTable differential drivers ----

let mact = new MeshAttributeCornerTable();
let mactSeams = new IntVector();

export function mactBegin(): void {
    mactSeams = new IntVector();
}

export function mactAddSeam(c: i32): void {
    mactSeams.push(c);
}

// Builds from the current corner table; returns num vertices or -1.
export function mactBuild(): i32 {
    mact = new MeshAttributeCornerTable();
    if (!mact.initEmpty(ct)) {
        return -1;
    }
    for (let i = 0; i < mactSeams.size(); i++) {
        mact.addSeamEdge(mactSeams.get(i));
    }
    if (!mact.recomputeVertices(null, null)) {
        return -1;
    }
    return mact.numVertices();
}

export function mactVertex(c: i32): i32 {
    return mact.vertex(c);
}

export function mactLeftMost(v: i32): i32 {
    return mact.leftMostCorner(v);
}

export function mactIsOnBoundary(v: i32): i32 {
    return mact.isOnBoundary(v) ? 1 : 0;
}

export function mactVertexParent(v: i32): i32 {
    return mact.vertexParent(v);
}

export function mactOpposite(c: i32): i32 {
    return mact.opposite(c);
}

// ---- Tex coords + geometric normal predictor differential drivers ----

import { PointAttribute } from "./lib/attributes/PointAttribute";
import { GeometryAttributeType } from "./lib/attributes/GeometryAttribute";
import { DataType } from "./lib/core/DracoTypes";
import { MeshPredictionSchemeData } from "./lib/prediction/MeshPredictionSchemeData";
import { MeshPredictionSchemeTexCoordsPortablePredictor } from "./lib/prediction/MeshPredictionSchemeTexCoordsPortablePredictor";
import { MeshPredictionSchemeGeometricNormalPredictorArea } from "./lib/prediction/MeshPredictionSchemeGeometricNormalPredictorArea";

let predMeshData = new MeshPredictionSchemeData();
let predD2c = new IntVector();
let predUv = new Int32Array(0);
let texPredictor: MeshPredictionSchemeTexCoordsPortablePredictor | null = null;
let gnPredictor: MeshPredictionSchemeGeometricNormalPredictorArea | null = null;
let gnOut = new Int32Array(3);

export function predSetup(): i32 {
    let nv = ct.numVertices();
    let pa = new PointAttribute();
    pa.initValues(GeometryAttributeType.POSITION, 3, DataType.INT32, false, nv);
    // Positions via LCG seed 333, identical to the C++ reference.
    let base = pa.buffer!.data().dataStart;
    let rng: u32 = 333;
    for (let i = 0; i < nv * 3; i++) {
        rng = rng * 1664525 + 1013904223;
        store<i32>(base + (<usize>i << 2), <i32>(rng % 1024));
    }

    predD2c = new IntVector();
    let v2d = new Int32Array(nv);
    let e2p = new Int32Array(nv);
    for (let i = 0; i < nv; i++) {
        predD2c.push(ct.leftMostCorner(i));
        v2d[i] = i;
        e2p[i] = i;
    }
    predMeshData = new MeshPredictionSchemeData();
    predMeshData.set(new Mesh(), ct, predD2c, v2d);

    // UV data via LCG seed 555.
    predUv = new Int32Array(nv * 2);
    rng = 555;
    for (let i = 0; i < nv * 2; i++) {
        rng = rng * 1664525 + 1013904223;
        predUv[i] = <i32>(rng % 1024);
    }

    let tex = new MeshPredictionSchemeTexCoordsPortablePredictor(predMeshData);
    tex.setPositionAttribute(pa);
    tex.setEntryToPointIdMap(e2p);
    // Orientations via LCG seed 999.
    tex.resizeOrientations(nv);
    rng = 999;
    for (let i = 0; i < nv; i++) {
        rng = rng * 1664525 + 1013904223;
        tex.setOrientation(i, ((rng >> 16) & 1) != 0);
    }
    texPredictor = tex;

    let gn = new MeshPredictionSchemeGeometricNormalPredictorArea(predMeshData);
    gn.setPositionAttribute(pa);
    gn.setEntryToPointIdMap(e2p);
    gnPredictor = gn;
    return nv;
}

export function texCase(dataId: i32): i32 {
    return texPredictor!.computePredictedValue(predD2c.get(dataId), predUv, dataId) ? 1 : 0;
}

export function texPredVal(i: i32): i32 {
    return texPredictor!.predictedValue()[i];
}

export function gnCase(dataId: i32): void {
    gnPredictor!.computePredictedValue(predD2c.get(dataId), gnOut);
}

export function gnPredVal(i: i32): i32 {
    return gnOut[i];
}
