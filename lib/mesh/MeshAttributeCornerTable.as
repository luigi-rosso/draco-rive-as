// Ported from draco mesh/mesh_attribute_corner_table.h/.cc. Stores attribute
// connectivity as seam-edge differences from the base corner table. The C++
// RecomputeVerticesInternal<bool> template collapses to a runtime flag.

import { CornerTableBase, CornerTable, VertexRingIterator, kInvalidCornerIndex, kInvalidVertexIndex } from "./CornerTable";
import { IntVector } from "./IntVector";
import { Mesh } from "./Mesh";
import { PointAttribute } from "../attributes/PointAttribute";

// vertexCorners holds the left-most corner per vertex: a corner whose
// swingLeft is invalid (next to a boundary or seam), or any corner when no
// such corner exists. oppositeCorners is the base table's own vector.
export class MeshAttributeCornerTable extends CornerTableBase {
    private isVertexOnSeam: Uint8Array = new Uint8Array(0);
    private _noInteriorSeams: bool = true;

    // Attribute entry id per vertex, exposed through vertexParent().
    private vertexToAttributeEntryIdMap: IntVector = new IntVector();

    private _cornerTable: CornerTable? = null;

    initEmpty(table: CornerTable): bool {
        this.isEdgeOnSeam = new Uint8Array(table.numCorners());
        this.isVertexOnSeam = new Uint8Array(table.numVertices());
        this.cornerToVertexMap.assign(table.numCorners(), kInvalidVertexIndex);
        this.oppositeCorners = table.oppositeCorners;
        this.vertexToAttributeEntryIdMap.clear();
        this.vertexToAttributeEntryIdMap.reserve(table.numVertices());
        this.vertexCorners.clear();
        this.vertexCorners.reserve(table.numVertices());
        this._cornerTable = table;
        this._noInteriorSeams = true;
        return true;
    }

    initFromAttribute(mesh: Mesh, table: CornerTable, att: PointAttribute): bool {
        if (!this.initEmpty(table)) {
            return false;
        }

        // Mark which mesh vertices are part of an attribute seam, since seams
        // need special handling.
        let numCorners = table.numCorners();
        for (let c = 0; c < numCorners; c++) {
            let f = table.face(c);
            if (table.isDegenerated(f)) {
                continue; // Ignore corners on degenerated faces.
            }
            let oppCorner = table.opposite(c);
            if (oppCorner == kInvalidCornerIndex) {
                // Boundary. Mark it as seam edge.
                unchecked(this.isEdgeOnSeam[c] = 1);
                unchecked(this.isVertexOnSeam[table.vertex(table.next(c))] = 1);
                unchecked(this.isVertexOnSeam[table.vertex(table.previous(c))] = 1);
                continue;
            }
            if (oppCorner < c) {
                continue; // Opposite corner was already processed.
            }

            let actC = c;
            let actSiblingC = oppCorner;
            for (let i = 0; i < 2; i++) {
                // Sibling corners: attached to the same vertex but divided by
                // the seam edge.
                actC = table.next(actC);
                actSiblingC = table.previous(actSiblingC);
                let pointId = mesh.cornerToPointId(actC);
                let siblingPointId = mesh.cornerToPointId(actSiblingC);
                if (att.mappedIndex(pointId) != att.mappedIndex(siblingPointId)) {
                    this._noInteriorSeams = false;
                    unchecked(this.isEdgeOnSeam[c] = 1);
                    unchecked(this.isEdgeOnSeam[oppCorner] = 1);
                    unchecked(this.isVertexOnSeam[table.vertex(table.next(c))] = 1);
                    unchecked(this.isVertexOnSeam[table.vertex(table.previous(c))] = 1);
                    unchecked(this.isVertexOnSeam[table.vertex(table.next(oppCorner))] = 1);
                    unchecked(this.isVertexOnSeam[table.vertex(table.previous(oppCorner))] = 1);
                    break;
                }
            }
        }
        return this.recomputeVertices(mesh, att);
    }

    addSeamEdge(c: i32): void {
        let table = this._cornerTable!;
        unchecked(this.isEdgeOnSeam[c] = 1);
        unchecked(this.isVertexOnSeam[table.vertex(table.next(c))] = 1);
        unchecked(this.isVertexOnSeam[table.vertex(table.previous(c))] = 1);

        let oppCorner = table.opposite(c);
        if (oppCorner != kInvalidCornerIndex) {
            this._noInteriorSeams = false;
            unchecked(this.isEdgeOnSeam[oppCorner] = 1);
            unchecked(this.isVertexOnSeam[table.vertex(table.next(oppCorner))] = 1);
            unchecked(this.isVertexOnSeam[table.vertex(table.previous(oppCorner))] = 1);
        }
    }

    // Recomputes vertices from the seam edges. With |mesh| and |att? the
    // vertex to attribute value mapping is identity.
    recomputeVertices(mesh: Mesh?, att: PointAttribute?): bool {
        let table = this._cornerTable!;
        let initVertexToAttributeEntryMap = mesh != null && att != null;
        this.vertexToAttributeEntryIdMap.clear();
        this.vertexCorners.clear();
        let numNewVertices = 0;
        let numVertices = table.numVertices();
        for (let v = 0; v < numVertices; v++) {
            let c = table.leftMostCorner(v);
            if (c == kInvalidCornerIndex) {
                continue; // Isolated vertex.
            }
            let firstVertId = numNewVertices++;
            if (initVertexToAttributeEntryMap) {
                let pointId = mesh!.cornerToPointId(c);
                this.vertexToAttributeEntryIdMap.push(<i32>att!.mappedIndex(pointId));
            } else {
                // Identity mapping.
                this.vertexToAttributeEntryIdMap.push(firstVertId);
            }
            let firstC = c;
            let actC: i32;
            // On a seam vertex, find the first attribute entry on the seam
            // when traversing in the CCW direction.
            if (unchecked(this.isVertexOnSeam[v]) != 0) {
                actC = this.swingLeft(firstC);
                while (actC != kInvalidCornerIndex) {
                    firstC = actC;
                    actC = this.swingLeft(actC);
                    if (actC == c) {
                        // Reached the initial corner, which should not happen
                        // when swinging left from |c|.
                        return false;
                    }
                }
            }
            this.cornerToVertexMap.set(firstC, firstVertId);
            this.vertexCorners.push(firstC);
            actC = table.swingRight(firstC);
            while (actC != kInvalidCornerIndex && actC != firstC) {
                if (this.isCornerOppositeToSeamEdge(table.next(actC))) {
                    firstVertId = numNewVertices++;
                    if (initVertexToAttributeEntryMap) {
                        let pointId = mesh!.cornerToPointId(actC);
                        this.vertexToAttributeEntryIdMap.push(<i32>att!.mappedIndex(pointId));
                    } else {
                        // Identity mapping.
                        this.vertexToAttributeEntryIdMap.push(firstVertId);
                    }
                    this.vertexCorners.push(actC);
                }
                this.cornerToVertexMap.set(actC, firstVertId);
                actC = table.swingRight(actC);
            }
        }
        return true;
    }

    isCornerOppositeToSeamEdge(corner: i32): bool {
        return unchecked(this.isEdgeOnSeam[corner]) != 0;
    }

    // True when the corner is attached to any attribute seam.
    isCornerOnSeam(corner: i32): bool {
        return unchecked(this.isVertexOnSeam[this._cornerTable!.vertex(corner)]) != 0;
    }

    numVertices(): i32 {
        return this.vertexToAttributeEntryIdMap.size();
    }

    numFaces(): i32 {
        return this._cornerTable!.numFaces();
    }

    numCorners(): i32 {
        return this._cornerTable!.numCorners();
    }

    // The attribute entry id associated to the given vertex.
    vertexParent(vert: i32): i32 {
        return this.vertexToAttributeEntryIdMap.get(vert);
    }

    isDegenerated(face: i32): bool {
        // Seams cannot change per-face degeneracy; delegate to the base table.
        return this._cornerTable!.isDegenerated(face);
    }

    noInteriorSeams(): bool {
        return this._noInteriorSeams;
    }

    cornerTable(): CornerTable {
        return this._cornerTable!;
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
}
