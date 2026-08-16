// Ported from draco compression/mesh/traverser/traverser_base.h. The C++
// template parameters collapse to CornerTableBase (virtual dispatch) and the
// single observer type the decoder uses.

import { CornerTableBase, kInvalidCornerIndex, kInvalidFaceIndex } from "./CornerTable";
import { MeshAttributeIndicesEncodingObserver } from "./MeshAttributeIndicesEncodingObserver";

export abstract class TraverserBase {
    protected _cornerTable: CornerTableBase | null = null;
    protected _observer: MeshAttributeIndicesEncodingObserver | null = null;
    private isFaceVisitedFlags: Uint8Array = new Uint8Array(0);
    private isVertexVisitedFlags: Uint8Array = new Uint8Array(0);

    init(cornerTable: CornerTableBase, observer: MeshAttributeIndicesEncodingObserver): void {
        this._cornerTable = cornerTable;
        this.isFaceVisitedFlags = new Uint8Array(cornerTable.numFaces());
        this.isVertexVisitedFlags = new Uint8Array(cornerTable.numVertices());
        this._observer = observer;
    }

    cornerTable(): CornerTableBase {
        return this._cornerTable!;
    }

    observer(): MeshAttributeIndicesEncodingObserver {
        return this._observer!;
    }

    isFaceVisited(faceId: i32): bool {
        if (faceId == kInvalidFaceIndex) {
            return true; // Invalid faces are always considered visited.
        }
        return unchecked(this.isFaceVisitedFlags[faceId]) != 0;
    }

    isFaceOfCornerVisited(corner: i32): bool {
        if (corner == kInvalidCornerIndex) {
            return true;
        }
        return unchecked(this.isFaceVisitedFlags[corner / 3]) != 0;
    }

    markFaceVisited(faceId: i32): void {
        unchecked(this.isFaceVisitedFlags[faceId] = 1);
    }

    isVertexVisited(vertId: i32): bool {
        return unchecked(this.isVertexVisitedFlags[vertId]) != 0;
    }

    markVertexVisited(vertId: i32): void {
        unchecked(this.isVertexVisitedFlags[vertId] = 1);
    }

    onTraversalStart(): void {}

    onTraversalEnd(): void {}

    traverseFromCorner(cornerId: i32): bool {
        return false;
    }
}
