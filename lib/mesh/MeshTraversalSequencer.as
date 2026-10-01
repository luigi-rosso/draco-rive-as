// Ported from draco compression/mesh/traverser/mesh_traversal_sequencer.h.
// The C++ base PointsSequencer owns the output point ids; here they live on
// this class behind phase A's PointsSequencer contract. The encoder-only
// SetCornerOrder path is omitted (the decoder always scans faces in order).

import { PointsSequencer } from "../attributes/PointsSequencer";
import { PointAttribute } from "../attributes/PointAttribute";
import { kInvalidVertexIndex } from "./CornerTable";
import { IntVector } from "./IntVector";
import { Mesh } from "./Mesh";
import { MeshAttributeIndicesEncodingData } from "./MeshAttributeIndicesEncodingData";
import { TraverserBase } from "./TraverserBase";

export class MeshTraversalSequencer extends PointsSequencer {
    private mesh: Mesh;
    private encodingData: MeshAttributeIndicesEncodingData;
    private traverser: TraverserBase? = null;
    private outPointIds: IntVector = new IntVector();

    constructor(mesh: Mesh, encodingData: MeshAttributeIndicesEncodingData) {
        super();
        this.mesh = mesh;
        this.encodingData = encodingData;
    }

    setTraverser(traverser: TraverserBase): void {
        this.traverser = traverser;
    }

    generateSequence(): bool {
        return this.generateSequenceInternal();
    }

    getOutputPointIds(): Int32Array {
        return this.outPointIds.view();
    }

    addPointId(pointId: i32): void {
        this.outPointIds.push(pointId);
    }

    updatePointToAttributeIndexMapping(attribute: PointAttribute): bool {
        let cornerTable = this.traverser!.cornerTable();
        let numPoints = this.mesh.numPoints();
        attribute.setExplicitMapping(numPoints);
        let numFaces = this.mesh.numFaces();
        let indicesMap = attribute.indicesMap();
        let vertexToAttEntry = this.encodingData.vertexToEncodedAttributeValueIndexMap;
        for (let f = 0; f < numFaces; f++) {
            for (let p = 0; p < 3; p++) {
                let corner = 3 * f + p;
                let pointId = this.mesh.cornerToPointId(corner);
                let vertId = cornerTable.vertex(corner);
                if (vertId == kInvalidVertexIndex) {
                    return false;
                }
                let attEntryId = unchecked(vertexToAttEntry[vertId]);
                // Unsigned compares like the C++ index types, so -1 (not yet
                // encoded) entries are rejected too.
                if (<u32>pointId >= <u32>numPoints || <u32>attEntryId >= <u32>numPoints) {
                    return false;
                }
                unchecked(indicesMap[pointId] = <u32>attEntryId);
            }
        }
        return true;
    }

    private generateSequenceInternal(): bool {
        let traverser = this.traverser!;
        // The number of points is expected to match the corner table's vertex
        // count.
        this.outPointIds.clear();
        this.outPointIds.reserve(traverser.cornerTable().numVertices());

        traverser.onTraversalStart();
        let numFaces = traverser.cornerTable().numFaces();
        for (let i = 0; i < numFaces; i++) {
            if (!traverser.traverseFromCorner(3 * i)) {
                return false;
            }
        }
        traverser.onTraversalEnd();
        return true;
    }
}
