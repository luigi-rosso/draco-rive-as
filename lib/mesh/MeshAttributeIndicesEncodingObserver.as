// Ported from draco compression/mesh/traverser/mesh_attribute_indices_encoding_observer.h.
// Generates the decoding order of attribute values from the mesh traversal.

import { CornerTableBase } from "./CornerTable";
import { Mesh } from "./Mesh";
import { MeshAttributeIndicesEncodingData } from "./MeshAttributeIndicesEncodingData";
import { PointsSequencer } from "../attributes/PointsSequencer";

export class MeshAttributeIndicesEncodingObserver {
    private attConnectivity: CornerTableBase;
    private encodingData: MeshAttributeIndicesEncodingData;
    private mesh: Mesh;
    private sequencer: PointsSequencer;

    constructor(
        connectivity: CornerTableBase, mesh: Mesh, sequencer: PointsSequencer,
        encodingData: MeshAttributeIndicesEncodingData) {
        this.attConnectivity = connectivity;
        this.mesh = mesh;
        this.sequencer = sequencer;
        this.encodingData = encodingData;
    }

    @inline
    onNewVertexVisited(vertex: i32, corner: i32): void {
        let pointId = this.mesh.cornerToPointId(corner);
        // Append the visited attribute to the encoding order.
        this.sequencer.addPointId(pointId);

        // Keep track of visited corners.
        this.encodingData.encodedAttributeValueIndexToCornerMap.push(corner);
        unchecked(this.encodingData.vertexToEncodedAttributeValueIndexMap[vertex] =
            this.encodingData.numValues);
        this.encodingData.numValues++;
    }
}
