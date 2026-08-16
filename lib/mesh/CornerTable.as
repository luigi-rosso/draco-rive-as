// Ported from draco mesh/corner_table.h/.cc. Corner indices are raw i32 with
// the C++ kInvalid* sentinels (uint32(-1)) represented as -1.
//
// CornerTableBase is the AS stand-in for draco's CornerTableT template
// parameter: CornerTable and MeshAttributeCornerTable share it so traversers,
// observers and prediction schemes are written once against virtual dispatch
// instead of being monomorphized per table type.

import { IntVector } from "./IntVector";

export const kInvalidCornerIndex: i32 = -1;
export const kInvalidVertexIndex: i32 = -1;
export const kInvalidFaceIndex: i32 = -1;

export abstract class CornerTableBase {
    numVertices(): i32 {
        return 0;
    }

    numCorners(): i32 {
        return 0;
    }

    numFaces(): i32 {
        return 0;
    }

    opposite(corner: i32): i32 {
        return kInvalidCornerIndex;
    }

    next(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return corner;
        }
        return corner % 3 == 2 ? corner - 2 : corner + 1;
    }

    previous(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return corner;
        }
        return corner % 3 == 0 ? corner + 2 : corner - 1;
    }

    vertex(corner: i32): i32 {
        return kInvalidVertexIndex;
    }

    face(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return kInvalidFaceIndex;
        }
        return corner / 3;
    }

    firstCorner(face: i32): i32 {
        if (face == kInvalidFaceIndex) {
            return kInvalidCornerIndex;
        }
        return face * 3;
    }

    localIndex(corner: i32): i32 {
        return corner % 3;
    }

    leftMostCorner(vert: i32): i32 {
        return kInvalidCornerIndex;
    }

    isDegenerated(face: i32): bool {
        return true;
    }

    //     *-------*
    //    / \     / \
    //   /   \   /   \
    //  /   sl\c/sr   \
    // *-------v-------*
    swingRight(corner: i32): i32 {
        return this.previous(this.opposite(this.previous(corner)));
    }

    swingLeft(corner: i32): i32 {
        return this.next(this.opposite(this.next(corner)));
    }

    getLeftCorner(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return kInvalidCornerIndex;
        }
        return this.opposite(this.previous(corner));
    }

    getRightCorner(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return kInvalidCornerIndex;
        }
        return this.opposite(this.next(corner));
    }

    isOnBoundary(vert: i32): bool {
        let corner = this.leftMostCorner(vert);
        if (corner == kInvalidCornerIndex) {
            return true;
        }
        return this.swingLeft(corner) == kInvalidCornerIndex;
    }
}

export class CornerTable extends CornerTableBase {
    // Each three consecutive corners represent one face.
    cornerToVertexMap: IntVector = new IntVector();
    oppositeCorners: IntVector = new IntVector();
    vertexCorners: IntVector = new IntVector();

    private _numOriginalVertices: i32 = 0;
    private _numDegeneratedFaces: i32 = 0;
    private _numIsolatedVertices: i32 = 0;
    private nonManifoldVertexParents: IntVector = new IntVector();

    // C++ Init(faces): faces are a flat array of 3 vertex indices per face.
    init(faces: Int32Array, numFaces: i32): bool {
        this.cornerToVertexMap.resize(numFaces * 3);
        for (let ci = 0; ci < numFaces * 3; ci++) {
            this.cornerToVertexMap.set(ci, faces[ci]);
        }
        let numVertices = this.computeOppositeCorners();
        if (numVertices < 0) {
            return false;
        }
        if (!this.breakNonManifoldEdges()) {
            return false;
        }
        return this.computeVertexCorners(numVertices);
    }

    reset(numFaces: i32, numVertices: i32): bool {
        if (numFaces < 0 || numVertices < 0) {
            return false;
        }
        if (<u32>numFaces > <u32>(0x7FFFFFFF / 3)) {
            return false;
        }
        this.cornerToVertexMap.assign(numFaces * 3, kInvalidVertexIndex);
        this.oppositeCorners.assign(numFaces * 3, kInvalidCornerIndex);
        this.vertexCorners.clear();
        this.vertexCorners.reserve(numVertices);
        return true;
    }

    numVertices(): i32 {
        return this.vertexCorners.size();
    }

    numCorners(): i32 {
        return this.cornerToVertexMap.size();
    }

    numFaces(): i32 {
        return this.cornerToVertexMap.size() / 3;
    }

    opposite(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return corner;
        }
        return this.oppositeCorners.get(corner);
    }

    vertex(corner: i32): i32 {
        if (corner == kInvalidCornerIndex) {
            return kInvalidVertexIndex;
        }
        return this.cornerToVertexMap.get(corner);
    }

    confidentVertex(corner: i32): i32 {
        return this.cornerToVertexMap.get(corner);
    }

    leftMostCorner(vert: i32): i32 {
        return this.vertexCorners.get(vert);
    }

    vertexParent(vert: i32): i32 {
        if (vert < this._numOriginalVertices) {
            return vert;
        }
        return this.nonManifoldVertexParents.get(vert - this._numOriginalVertices);
    }

    isValid(corner: i32): bool {
        return this.vertex(corner) != kInvalidVertexIndex;
    }

    valence(vert: i32): i32 {
        if (vert == kInvalidVertexIndex) {
            return -1;
        }
        return this.confidentValence(vert);
    }

    confidentValence(vert: i32): i32 {
        let iter = new VertexRingIterator(this, vert);
        let valence = 0;
        while (!iter.end()) {
            valence++;
            iter.next();
        }
        return valence;
    }

    numNewVertices(): i32 {
        return this.numVertices() - this._numOriginalVertices;
    }

    numOriginalVertices(): i32 {
        return this._numOriginalVertices;
    }

    numDegeneratedFaces(): i32 {
        return this._numDegeneratedFaces;
    }

    numIsolatedVertices(): i32 {
        return this._numIsolatedVertices;
    }

    isDegenerated(face: i32): bool {
        if (face == kInvalidFaceIndex) {
            return true;
        }
        let firstFaceCorner = this.firstCorner(face);
        let v0 = this.vertex(firstFaceCorner);
        let v1 = this.vertex(this.next(firstFaceCorner));
        let v2 = this.vertex(this.previous(firstFaceCorner));
        return v0 == v1 || v0 == v2 || v1 == v2;
    }

    setOppositeCorner(corner: i32, oppCorner: i32): void {
        this.oppositeCorners.set(corner, oppCorner);
    }

    setOppositeCorners(corner0: i32, corner1: i32): void {
        if (corner0 != kInvalidCornerIndex) {
            this.setOppositeCorner(corner0, corner1);
        }
        if (corner1 != kInvalidCornerIndex) {
            this.setOppositeCorner(corner1, corner0);
        }
    }

    mapCornerToVertex(corner: i32, vert: i32): void {
        this.cornerToVertexMap.set(corner, vert);
    }

    addNewVertex(): i32 {
        this.vertexCorners.push(kInvalidCornerIndex);
        return this.vertexCorners.size() - 1;
    }

    setLeftMostCorner(vert: i32, corner: i32): void {
        if (vert != kInvalidVertexIndex) {
            this.vertexCorners.set(vert, corner);
        }
    }

    updateVertexToCornerMap(vert: i32): void {
        let firstC = this.vertexCorners.get(vert);
        if (firstC == kInvalidCornerIndex) {
            return; // Isolated vertex.
        }
        let actC = this.swingLeft(firstC);
        let c = firstC;
        while (actC != kInvalidCornerIndex && actC != firstC) {
            c = actC;
            actC = this.swingLeft(actC);
        }
        if (actC != firstC) {
            this.vertexCorners.set(vert, c);
        }
    }

    setNumVertices(numVertices: i32): void {
        this.vertexCorners.resize(numVertices, kInvalidCornerIndex);
    }

    makeVertexIsolated(vert: i32): void {
        this.vertexCorners.set(vert, kInvalidCornerIndex);
    }

    isVertexIsolated(vert: i32): bool {
        return this.leftMostCorner(vert) == kInvalidCornerIndex;
    }

    makeFaceInvalid(face: i32): void {
        if (face != kInvalidFaceIndex) {
            let firstCorner = this.firstCorner(face);
            for (let i = 0; i < 3; i++) {
                this.cornerToVertexMap.set(firstCorner + i, kInvalidVertexIndex);
            }
        }
    }

    // Returns the number of vertices, or -1 on error.
    private computeOppositeCorners(): i32 {
        let numCorners = this.numCorners();
        this.oppositeCorners.resize(numCorners, kInvalidCornerIndex);

        // Opposite corners are found by tracking outgoing half-edges per
        // vertex: each processed half-edge either matches its sibling on the
        // sink vertex (connect and remove) or is stored on its source vertex.
        let numCornersOnVertices = new IntVector(numCorners);
        for (let c = 0; c < numCorners; c++) {
            let v1 = this.vertex(c);
            if (v1 >= numCornersOnVertices.size()) {
                numCornersOnVertices.resize(v1 + 1, 0);
            }
            numCornersOnVertices.set(v1, numCornersOnVertices.get(v1) + 1);
        }

        // Half-edge storage: parallel arrays of <sink vertex, edge corner>,
        // partitioned per vertex by |vertexOffset|.
        let vertexEdgeSinks = new Int32Array(numCorners);
        let vertexEdgeCorners = new Int32Array(numCorners);
        vertexEdgeSinks.fill(kInvalidVertexIndex);
        vertexEdgeCorners.fill(kInvalidCornerIndex);

        let numVertices = numCornersOnVertices.size();
        let vertexOffset = new Int32Array(numVertices);
        let offset = 0;
        for (let i = 0; i < numVertices; i++) {
            vertexOffset[i] = offset;
            offset += numCornersOnVertices.get(i);
        }

        for (let c = 0; c < numCorners; c++) {
            let tipV = this.vertex(c);
            let sourceV = this.vertex(this.next(c));
            let sinkV = this.vertex(this.previous(c));

            let faceIndex = this.face(c);
            if (c == this.firstCorner(faceIndex)) {
                // Ignore degenerated faces.
                let v0 = this.vertex(c);
                if (v0 == sourceV || v0 == sinkV || sourceV == sinkV) {
                    this._numDegeneratedFaces++;
                    c += 2; // Skip the next two corners of the same face.
                    continue;
                }
            }

            let oppositeC = kInvalidCornerIndex;
            let numCornersOnVert = numCornersOnVertices.get(sinkV);
            offset = vertexOffset[sinkV];
            for (let i = 0; i < numCornersOnVert; i++, offset++) {
                let otherV = vertexEdgeSinks[offset];
                if (otherV == kInvalidVertexIndex) {
                    break; // No matching half-edge on the sink vertex.
                }
                if (otherV == sourceV) {
                    if (tipV == this.vertex(vertexEdgeCorners[offset])) {
                        continue; // Don't connect mirrored faces.
                    }
                    oppositeC = vertexEdgeCorners[offset];
                    // Remove the half-edge; remap subsequent ones a slot down.
                    for (let j = i + 1; j < numCornersOnVert; j++, offset++) {
                        vertexEdgeSinks[offset] = vertexEdgeSinks[offset + 1];
                        vertexEdgeCorners[offset] = vertexEdgeCorners[offset + 1];
                        if (vertexEdgeSinks[offset] == kInvalidVertexIndex) {
                            break; // Unused half-edge reached.
                        }
                    }
                    vertexEdgeSinks[offset] = kInvalidVertexIndex;
                    break;
                }
            }
            if (oppositeC == kInvalidCornerIndex) {
                // No opposite corner found. Insert the new edge.
                let numCornersOnSourceVert = numCornersOnVertices.get(sourceV);
                offset = vertexOffset[sourceV];
                for (let i = 0; i < numCornersOnSourceVert; i++, offset++) {
                    if (vertexEdgeSinks[offset] == kInvalidVertexIndex) {
                        vertexEdgeSinks[offset] = sinkV;
                        vertexEdgeCorners[offset] = c;
                        break;
                    }
                }
            } else {
                this.oppositeCorners.set(c, oppositeC);
                this.oppositeCorners.set(oppositeC, c);
            }
        }
        return numVertices;
    }

    // Breaks non-manifold edges caused by folds in a vertex 1-ring; the
    // disconnected patches then get new vertices in computeVertexCorners.
    private breakNonManifoldEdges(): bool {
        let numCorners = this.numCorners();
        let visitedCorners = new Uint8Array(numCorners);
        let sinkVerts = new IntVector();
        let sinkCorners = new IntVector();
        let meshConnectivityUpdated = false;
        do {
            meshConnectivityUpdated = false;
            for (let c = 0; c < numCorners; c++) {
                if (visitedCorners[c] != 0) {
                    continue;
                }
                sinkVerts.clear();
                sinkCorners.clear();

                // Swing all the way left to the left-most corner on this
                // vertex.
                let firstC = c;
                let currentC = c;
                let nextC = this.swingLeft(currentC);
                while (nextC != firstC && nextC != kInvalidCornerIndex &&
                       visitedCorners[nextC] == 0) {
                    currentC = nextC;
                    nextC = this.swingLeft(currentC);
                }

                firstC = currentC;

                // Swing right from the first corner; every edge (identified by
                // its sink vertex) must be unique.
                do {
                    visitedCorners[currentC] = 1;
                    let sinkC = this.next(currentC);
                    let sinkV = this.cornerToVertexMap.get(sinkC);

                    let edgeCorner = this.previous(currentC);
                    let vertexConnectivityUpdated = false;
                    for (let i = 0; i < sinkVerts.size(); i++) {
                        if (sinkVerts.get(i) != sinkV) {
                            continue;
                        }
                        // Sink vertex was already processed.
                        let otherEdgeCorner = sinkCorners.get(i);
                        let oppEdgeCorner = this.opposite(edgeCorner);

                        if (oppEdgeCorner == otherEdgeCorner) {
                            // Closing the loop; connectivity is fine.
                            continue;
                        }

                        // Break the connectivity on the non-manifold edge.
                        let oppOtherEdgeCorner = this.opposite(otherEdgeCorner);
                        if (oppEdgeCorner != kInvalidCornerIndex) {
                            this.setOppositeCorner(oppEdgeCorner, kInvalidCornerIndex);
                        }
                        if (oppOtherEdgeCorner != kInvalidCornerIndex) {
                            this.setOppositeCorner(oppOtherEdgeCorner, kInvalidCornerIndex);
                        }
                        this.setOppositeCorner(edgeCorner, kInvalidCornerIndex);
                        this.setOppositeCorner(otherEdgeCorner, kInvalidCornerIndex);
                        vertexConnectivityUpdated = true;
                        break;
                    }
                    if (vertexConnectivityUpdated) {
                        // Connectivity changed; corners on this vertex need to
                        // be processed again.
                        meshConnectivityUpdated = true;
                        break;
                    }
                    sinkVerts.push(this.cornerToVertexMap.get(this.previous(currentC)));
                    sinkCorners.push(sinkC);

                    currentC = this.swingRight(currentC);
                } while (currentC != firstC && currentC != kInvalidCornerIndex);
            }
        } while (meshConnectivityUpdated);
        return true;
    }

    private computeVertexCorners(numVertices: i32): bool {
        this._numOriginalVertices = numVertices;
        this.vertexCorners.resize(numVertices, kInvalidCornerIndex);
        // Visited flags detect non-manifold vertices (grows with new splits).
        let visitedVertices = new IntVector(numVertices);
        visitedVertices.resize(numVertices, 0);
        let visitedCorners = new Uint8Array(this.numCorners());

        let numFaces = this.numFaces();
        for (let f = 0; f < numFaces; f++) {
            let firstFaceCorner = this.firstCorner(f);
            if (this.isDegenerated(f)) {
                continue;
            }

            for (let k = 0; k < 3; k++) {
                let c = firstFaceCorner + k;
                if (visitedCorners[c] != 0) {
                    continue;
                }
                let v = this.cornerToVertexMap.get(c);
                // Only track the corner with a boundary on the left when the
                // vertex lies on a boundary, so all related corners are
                // reachable by swingRight.
                let isNonManifoldVertex = false;
                if (visitedVertices.get(v) != 0) {
                    // Unvisited corner on a visited vertex: non-manifold
                    // vertex; create a new one for it.
                    this.vertexCorners.push(kInvalidCornerIndex);
                    this.nonManifoldVertexParents.push(v);
                    visitedVertices.push(0);
                    v = numVertices++;
                    isNonManifoldVertex = true;
                }
                visitedVertices.set(v, 1);

                // Swing all the way left, marking corners on the way.
                let actC = c;
                while (actC != kInvalidCornerIndex) {
                    visitedCorners[actC] = 1;
                    // Vertex ends up pointing to the left-most corner.
                    this.vertexCorners.set(v, actC);
                    if (isNonManifoldVertex) {
                        this.cornerToVertexMap.set(actC, v);
                    }
                    actC = this.swingLeft(actC);
                    if (actC == c) {
                        break; // Full circle reached.
                    }
                }
                if (actC == kInvalidCornerIndex) {
                    // Open boundary: swing right from the initial corner to
                    // mark the remaining corners.
                    actC = this.swingRight(c);
                    while (actC != kInvalidCornerIndex) {
                        visitedCorners[actC] = 1;
                        if (isNonManifoldVertex) {
                            this.cornerToVertexMap.set(actC, v);
                        }
                        actC = this.swingRight(actC);
                    }
                }
            }
        }

        this._numIsolatedVertices = 0;
        for (let i = 0; i < visitedVertices.size(); i++) {
            if (visitedVertices.get(i) == 0) {
                this._numIsolatedVertices++;
            }
        }
        return true;
    }
}

// Iterates over vertices in the 1-ring around a vertex
// (draco mesh/corner_table_iterators.h VertexRingIterator).
export class VertexRingIterator {
    private table: CornerTableBase;
    private startCorner: i32;
    private corner: i32;
    private leftTraversal: bool;

    constructor(table: CornerTableBase, vertId: i32) {
        this.table = table;
        this.startCorner = table.leftMostCorner(vertId);
        this.corner = this.startCorner;
        this.leftTraversal = true;
    }

    reset(table: CornerTableBase, vertId: i32): void {
        this.table = table;
        this.startCorner = table.leftMostCorner(vertId);
        this.corner = this.startCorner;
        this.leftTraversal = true;
    }

    // The last visited ring vertex.
    ringVertex(): i32 {
        let ringCorner = this.leftTraversal
            ? this.table.previous(this.corner)
            : this.table.next(this.corner);
        return this.table.vertex(ringCorner);
    }

    // A corner opposite to the edge from the ring vertex to the center vertex.
    edgeCorner(): i32 {
        return this.leftTraversal
            ? this.table.next(this.corner)
            : this.table.previous(this.corner);
    }

    end(): bool {
        return this.corner == kInvalidCornerIndex;
    }

    next(): void {
        if (this.leftTraversal) {
            this.corner = this.table.swingLeft(this.corner);
            if (this.corner == kInvalidCornerIndex) {
                // Open boundary reached.
                this.corner = this.startCorner;
                this.leftTraversal = false;
            } else if (this.corner == this.startCorner) {
                // End reached.
                this.corner = kInvalidCornerIndex;
            }
        } else {
            this.corner = this.table.swingRight(this.corner);
        }
    }
}

// Iterates over corners attached to a vertex
// (draco mesh/corner_table_iterators.h VertexCornersIterator).
export class VertexCornersIterator {
    private table: CornerTableBase;
    private startCorner: i32;
    private _corner: i32;
    private leftTraversal: bool;

    constructor(table: CornerTableBase, startCorner: i32) {
        this.table = table;
        this.startCorner = startCorner;
        this._corner = startCorner;
        this.leftTraversal = true;
    }

    static fromVertex(table: CornerTableBase, vertId: i32): VertexCornersIterator {
        return new VertexCornersIterator(table, table.leftMostCorner(vertId));
    }

    resetFromCorner(table: CornerTableBase, startCorner: i32): void {
        this.table = table;
        this.startCorner = startCorner;
        this._corner = startCorner;
        this.leftTraversal = true;
    }

    corner(): i32 {
        return this._corner;
    }

    end(): bool {
        return this._corner == kInvalidCornerIndex;
    }

    next(): void {
        if (this.leftTraversal) {
            this._corner = this.table.swingLeft(this._corner);
            if (this._corner == kInvalidCornerIndex) {
                // Open boundary reached.
                this._corner = this.table.swingRight(this.startCorner);
                this.leftTraversal = false;
            } else if (this._corner == this.startCorner) {
                // End reached.
                this._corner = kInvalidCornerIndex;
            }
        } else {
            this._corner = this.table.swingRight(this._corner);
        }
    }
}
