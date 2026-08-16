// Ported from draco compression/attributes/mesh_attribute_indices_encoding_data.h.

import { IntVector } from "./IntVector";

export class MeshAttributeIndicesEncodingData {
    // Corner id per encoded attribute value entry, in decode order. Only one
    // corner is stored per attribute value; prediction schemes rely on it.
    encodedAttributeValueIndexToCornerMap: IntVector = new IntVector();

    // Attribute entry id per vertex; -1 when not encoded/decoded yet.
    vertexToEncodedAttributeValueIndexMap: Int32Array = new Int32Array(0);

    // Total number of encoded/decoded attribute entries.
    numValues: i32 = 0;

    init(numVertices: i32): void {
        this.vertexToEncodedAttributeValueIndexMap = new Int32Array(numVertices);
        // One value is expected for each vertex.
        this.encodedAttributeValueIndexToCornerMap.clear();
        this.encodedAttributeValueIndexToCornerMap.reserve(numVertices);
        this.numValues = 0;
    }
}
