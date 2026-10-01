// Ported from draco compression/mesh/mesh_edgebreaker_decoder_impl.h/.cc
// (bitstream >= 2.2 subset; DRACO_BACKWARDS_COMPATIBILITY branches dropped).
// Spirale-reversi decoding of the edgebreaker symbol stream; symbols arrive in
// reverse encoding order so they are processed one by one.
//
// Deviations from C++, all documented in the phase B manifest:
//  * The TraversalDecoderT template becomes a MeshEdgebreakerTraversalDecoder
//    base reference passed to the constructor.
//  * topology_split_active_corners (unordered_map keyed by decoder symbol id)
//    becomes a flat Int32Array indexed by symbol id, -1 meaning absent.
//  * Members that C++ only clears but never reads on the decoder path
//    (vertex_traversal_length_, processed_corner_ids_,
//    processed_connectivity_corners_, hole_event_data_,
//    new_to_parent_vertex_map_) are omitted.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointsSequencer } from "../attributes/PointsSequencer";
import {
    CornerTable,
    VertexCornersIterator,
    kInvalidCornerIndex,
    kInvalidVertexIndex,
} from "./CornerTable";
import { IntVector } from "./IntVector";
import { Mesh, MeshAttributeElementType } from "./Mesh";
import { MeshAttributeCornerTable } from "./MeshAttributeCornerTable";
import { MeshAttributeIndicesEncodingData } from "./MeshAttributeIndicesEncodingData";
import { MeshAttributeIndicesEncodingObserver } from "./MeshAttributeIndicesEncodingObserver";
import { MeshEdgebreakerDecoderHost } from "./MeshEdgebreakerDecoderHost";
import { MeshEdgebreakerTraversalDecoder } from "./MeshEdgebreakerTraversalDecoder";
import {
    EdgebreakerTopologyBitPattern,
    EdgeFaceName,
    TopologySplitEventData,
} from "./MeshEdgebreakerShared";
import { MeshTraversalSequencer } from "./MeshTraversalSequencer";
import { TraverserBase } from "./TraverserBase";
import { DepthFirstTraverser } from "./DepthFirstTraverser";
import { MaxPredictionDegreeTraverser } from "./MaxPredictionDegreeTraverser";
import { MeshTraversalMethod } from "../config/CompressionShared";

// Data for one non-position attribute (C++ AttributeData).
export class AttributeData {
    // Id of the attributes decoder that decodes this attribute data.
    decoderId: i32 = -1;
    connectivityData: MeshAttributeCornerTable = new MeshAttributeCornerTable();
    // When false the base corner table is used instead.
    isConnectivityUsed: bool = true;
    encodingData: MeshAttributeIndicesEncodingData = new MeshAttributeIndicesEncodingData();
    // Opposite corners to attribute seam edges.
    attributeSeamCorners: IntVector = new IntVector();
}

export class MeshEdgebreakerDecoderImpl {
    private decoder: MeshEdgebreakerDecoderHost? = null;
    private cornerTable: CornerTable? = null;

    // Decoded topology split events, consumed from the back.
    private topologySplitData: Array<TopologySplitEventData> = new Array<TopologySplitEventData>();

    // Configuration and initial corner of each traversal.
    private initFaceConfigurations: IntVector = new IntVector();
    private initCorners: IntVector = new IntVector();

    private lastSymbolId: i32 = -1;
    private lastVertId: i32 = -1;
    private lastFaceId: i32 = -1;

    // Vertices on open boundaries.
    private isVertHole: Uint8Array = new Uint8Array(0);

    private numNewVertices: i32 = 0;
    private numEncodedVertices: i32 = 0;

    private posEncodingData: MeshAttributeIndicesEncodingData = new MeshAttributeIndicesEncodingData();
    private posDataDecoderId: i32 = -1;

    private attributeData: Array<AttributeData> = new Array<AttributeData>();

    private traversalDecoder: MeshEdgebreakerTraversalDecoder;

    constructor(traversalDecoder: MeshEdgebreakerTraversalDecoder) {
        this.traversalDecoder = traversalDecoder;
    }

    init(decoder: MeshEdgebreakerDecoderHost): bool {
        this.decoder = decoder;
        return true;
    }

    getCornerTable(): CornerTable? {
        return this.cornerTable;
    }

    getAttributeCornerTable(attId: i32): MeshAttributeCornerTable? {
        let decoder = this.decoder!;
        for (let i = 0; i < this.attributeData.length; i++) {
            let decoderId = this.attributeData[i].decoderId;
            if (decoderId < 0 || decoderId >= decoder.numAttributesDecoders()) {
                continue;
            }
            let numAttributes = decoder.attributesDecoderNumAttributes(decoderId);
            for (let j = 0; j < numAttributes; j++) {
                if (decoder.attributesDecoderAttributeId(decoderId, j) == attId) {
                    if (this.attributeData[i].isConnectivityUsed) {
                        return this.attributeData[i].connectivityData;
                    }
                    return null;
                }
            }
        }
        return null;
    }

    getAttributeEncodingData(attId: i32): MeshAttributeIndicesEncodingData {
        let decoder = this.decoder!;
        for (let i = 0; i < this.attributeData.length; i++) {
            let decoderId = this.attributeData[i].decoderId;
            if (decoderId < 0 || decoderId >= decoder.numAttributesDecoders()) {
                continue;
            }
            let numAttributes = decoder.attributesDecoderNumAttributes(decoderId);
            for (let j = 0; j < numAttributes; j++) {
                if (decoder.attributesDecoderAttributeId(decoderId, j) == attId) {
                    return this.attributeData[i].encodingData;
                }
            }
        }
        return this.posEncodingData;
    }

    private createVertexTraversalSequencer(
        traverser: TraverserBase,
        encodingData: MeshAttributeIndicesEncodingData): PointsSequencer {
        let mesh = this.decoder!.mesh();
        let traversalSequencer = new MeshTraversalSequencer(mesh, encodingData);
        let attObserver = new MeshAttributeIndicesEncodingObserver(
            this.cornerTable!, mesh, traversalSequencer, encodingData);
        traverser.init(this.cornerTable!, attObserver);
        traversalSequencer.setTraverser(traverser);
        return traversalSequencer;
    }

    createAttributesDecoder(attDecoderId: i32): bool {
        let decoder = this.decoder!;
        let buffer = decoder.buffer();
        let attDataId = buffer.decodeInt8();
        if (buffer.err) {
            return false;
        }
        let decoderType = buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }

        if (attDataId >= 0) {
            if (attDataId >= this.attributeData.length) {
                return false; // Unexpected attribute data.
            }
            // The attribute data must not be mapped to a different attributes
            // decoder already.
            if (this.attributeData[attDataId].decoderId >= 0) {
                return false;
            }
            this.attributeData[attDataId].decoderId = attDecoderId;
        } else {
            // The attributes decoder uses the position encoding data.
            if (this.posDataDecoderId >= 0) {
                return false; // Some other decoder already uses it.
            }
            this.posDataDecoderId = attDecoderId;
        }

        let traversalMethodEncoded = buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }
        if (traversalMethodEncoded >= <u32>MeshTraversalMethod.NUM_TRAVERSAL_METHODS) {
            return false;
        }
        let traversalMethod = <i32>traversalMethodEncoded;

        let mesh = decoder.mesh();
        let sequencer: PointsSequencer? = null;

        if (decoderType == <u32>MeshAttributeElementType.MESH_VERTEX_ATTRIBUTE) {
            // Per-vertex attribute decoder.
            let encodingData: MeshAttributeIndicesEncodingData;
            if (attDataId < 0) {
                encodingData = this.posEncodingData;
            } else {
                encodingData = this.attributeData[attDataId].encodingData;
                // The attribute connectivity data must not be used later on.
                this.attributeData[attDataId].isConnectivityUsed = false;
            }
            if (traversalMethod == MeshTraversalMethod.MESH_TRAVERSAL_PREDICTION_DEGREE) {
                sequencer = this.createVertexTraversalSequencer(
                    new MaxPredictionDegreeTraverser(), encodingData);
            } else if (traversalMethod == MeshTraversalMethod.MESH_TRAVERSAL_DEPTH_FIRST) {
                sequencer = this.createVertexTraversalSequencer(
                    new DepthFirstTraverser(), encodingData);
            } else {
                return false; // Unsupported method.
            }
        } else {
            if (traversalMethod != MeshTraversalMethod.MESH_TRAVERSAL_DEPTH_FIRST) {
                return false; // Unsupported method.
            }
            if (attDataId < 0) {
                return false; // Attribute data must be specified.
            }

            // Per-corner attribute decoder.
            let encodingData = this.attributeData[attDataId].encodingData;
            let cornerTable = this.attributeData[attDataId].connectivityData;

            let traversalSequencer = new MeshTraversalSequencer(mesh, encodingData);
            let attObserver = new MeshAttributeIndicesEncodingObserver(
                cornerTable, mesh, traversalSequencer, encodingData);
            let attTraverser = new DepthFirstTraverser();
            attTraverser.init(cornerTable, attObserver);

            traversalSequencer.setTraverser(attTraverser);
            sequencer = traversalSequencer;
        }

        if (sequencer == null) {
            return false;
        }
        return decoder.setAttributesDecoder(attDecoderId, sequencer);
    }

    decodeConnectivity(): bool {
        let decoder = this.decoder!;
        let buffer = decoder.buffer();
        this.numNewVertices = 0;

        let numEncodedVertices = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        this.numEncodedVertices = <i32>numEncodedVertices;

        let numFaces = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        if (numFaces > <u32>(0x7FFFFFFF / 3)) {
            return false; // Draco cannot handle this many faces.
        }

        if (numEncodedVertices > numFaces * 3) {
            return false; // There cannot be more vertices than 3 * numFaces.
        }

        // Minimum number of face edges assuming each edge is shared between
        // two faces, versus the maximum number of edges a simple connected
        // graph on the encoded vertices can have.
        let minNumFaceEdges: u32 = 3 * numFaces / 2;
        let numEncodedVertices64 = <u64>numEncodedVertices;
        let maxNumVertexEdges: u64 = numEncodedVertices64 * (numEncodedVertices64 - 1) / 2;
        if (maxNumVertexEdges < <u64>minNumFaceEdges) {
            // A manifold mesh with these properties is impossible.
            return false;
        }

        let numAttributeData = buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }

        let numEncodedSymbols = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }

        if (numFaces < numEncodedSymbols) {
            // The number of faces needs to be the same or greater than the
            // number of symbols (the initial face may not be encoded as one).
            return false;
        }
        let maxEncodedFaces = numEncodedSymbols + (numEncodedSymbols / 3);
        if (numFaces > maxEncodedFaces) {
            // Faces can only be 1 1/3 times the number of encoded symbols
            // (all new components starting with interior triangles).
            return false;
        }

        let numEncodedSplitSymbols = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        if (numEncodedSplitSymbols > numEncodedSymbols) {
            return false; // Split symbols are a subset of all symbols.
        }

        // Decode topology (connectivity).
        let cornerTable = new CornerTable();
        this.cornerTable = cornerTable;
        this.topologySplitData = new Array<TopologySplitEventData>();
        this.initFaceConfigurations.clear();
        this.initCorners.clear();

        this.lastSymbolId = -1;
        this.lastFaceId = -1;
        this.lastVertId = -1;

        // One attribute data for each attribute decoder.
        this.attributeData = new Array<AttributeData>();
        for (let i: u32 = 0; i < numAttributeData; i++) {
            this.attributeData.push(new AttributeData());
        }

        if (!cornerTable.reset(
                <i32>numFaces, this.numEncodedVertices + <i32>numEncodedSplitSymbols)) {
            return false;
        }

        // Start with all vertices marked as holes (boundaries); only vertices
        // decoded with TOPOLOGY_C and the initial faces become non-holes. The
        // array is larger because split symbols create extra vertices that get
        // eliminated during deduplication.
        this.isVertHole = new Uint8Array(this.numEncodedVertices + <i32>numEncodedSplitSymbols);
        this.isVertHole.fill(1);

        if (this.decodeHoleAndTopologySplitEvents(buffer) == -1) {
            return false;
        }

        this.traversalDecoder.init(buffer, cornerTable);
        // One extra vertex for each split symbol.
        this.traversalDecoder.setNumEncodedVertices(
            this.numEncodedVertices + <i32>numEncodedSplitSymbols);
        this.traversalDecoder.setNumAttributeData(<i32>numAttributeData);

        let traversalEndBuffer = new DecoderBuffer();
        if (!this.traversalDecoder.start(traversalEndBuffer)) {
            return false;
        }

        for (let i = 0; i < this.attributeData.length; i++) {
            this.attributeData[i].attributeSeamCorners.reserve(<i32>numFaces * 3);
        }
        let numConnectivityVerts = this.decodeConnectivitySymbols(<i32>numEncodedSymbols);
        if (numConnectivityVerts == -1) {
            return false;
        }

        // Set the main buffer to the end of the traversal.
        buffer.initView(traversalEndBuffer.dataHead(), -1, buffer.bitstreamVersion);

        // Decode connectivity of non-position attributes.
        if (this.attributeData.length > 0) {
            let numCorners = cornerTable.numCorners();
            for (let ci = 0; ci < numCorners; ci += 3) {
                if (!this.decodeAttributeConnectivitiesOnFace(ci)) {
                    return false;
                }
            }
        }
        this.traversalDecoder.done();

        // Prepare data structures for the non-position attribute connectivity.
        for (let i = 0; i < this.attributeData.length; i++) {
            let data = this.attributeData[i];
            data.connectivityData.initEmpty(cornerTable);
            // Add all seams.
            for (let j = 0; j < data.attributeSeamCorners.size(); j++) {
                data.connectivityData.addSeamEdge(data.attributeSeamCorners.get(j));
            }
            // Recompute vertices from the newly added seam edges.
            if (!data.connectivityData.recomputeVertices(null, null)) {
                return false;
            }
        }

        this.posEncodingData.init(cornerTable.numVertices());
        for (let i = 0; i < this.attributeData.length; i++) {
            // Preallocate the vertex-to-value map with the larger of the base
            // and attribute corner table vertex counts (the attribute decoder
            // may use either).
            let attConnectivityVerts = this.attributeData[i].connectivityData.numVertices();
            if (attConnectivityVerts < cornerTable.numVertices()) {
                attConnectivityVerts = cornerTable.numVertices();
            }
            this.attributeData[i].encodingData.init(attConnectivityVerts);
        }
        return this.assignPointsToCorners(numConnectivityVerts);
    }

    onAttributesDecoded(): bool {
        return true;
    }

    // True when the current symbol was part of a topology split event, i.e.
    // the face was connected to the left edge of a TOPOLOGY_S face.
    // outSplit[0] receives the source edge, outSplit[1] the encoder split
    // symbol id (-1 signals a broken stream).
    private isTopologySplit(encoderSymbolId: i32, outSplit: Int32Array): bool {
        if (this.topologySplitData.length == 0) {
            return false;
        }
        let last = this.topologySplitData[this.topologySplitData.length - 1];
        if (last.sourceSymbolId > <u32>encoderSymbolId) {
            // The desired source symbol was missed or the input was tampered
            // with (|encoderSymbolId| keeps decreasing).
            outSplit[1] = -1;
            return true;
        }
        if (last.sourceSymbolId != <u32>encoderSymbolId) {
            return false;
        }
        outSplit[0] = <i32>last.sourceEdge;
        outSplit[1] = <i32>last.splitSymbolId;
        this.topologySplitData.pop();
        return true;
    }

    // Returns the number of parsed bytes, or -1 on error. Hole events do not
    // appear in bitstreams >= 2.1 and are not stored.
    private decodeHoleAndTopologySplitEvents(decoderBuffer: DecoderBuffer): i32 {
        let numTopologySplits = decoderBuffer.decodeVarintUint32();
        if (decoderBuffer.err) {
            return -1;
        }
        if (numTopologySplits > 0) {
            if (numTopologySplits > <u32>this.cornerTable!.numFaces()) {
                return -1;
            }
            // Source and split symbol ids are delta and varint coded.
            let lastSourceSymbolId: u32 = 0;
            for (let i: u32 = 0; i < numTopologySplits; i++) {
                let eventData = new TopologySplitEventData();
                let delta = decoderBuffer.decodeVarintUint32();
                if (decoderBuffer.err) {
                    return -1;
                }
                eventData.sourceSymbolId = delta + lastSourceSymbolId;
                delta = decoderBuffer.decodeVarintUint32();
                if (decoderBuffer.err) {
                    return -1;
                }
                if (delta > eventData.sourceSymbolId) {
                    return -1;
                }
                eventData.splitSymbolId = eventData.sourceSymbolId - delta;
                lastSourceSymbolId = eventData.sourceSymbolId;
                this.topologySplitData.push(eventData);
            }
            // Split edges come from a direct bit decoder.
            decoderBuffer.startBitDecoding(false);
            for (let i: u32 = 0; i < numTopologySplits; i++) {
                let edgeData = decoderBuffer.decodeLeastSignificantBits32(1);
                this.topologySplitData[i].sourceEdge = edgeData & 1;
            }
            decoderBuffer.endBitDecoding();
            if (decoderBuffer.err) {
                return -1;
            }
        }
        return decoderBuffer.decodedSize();
    }

    // Decodes connectivity between vertices. Returns the number of decoded
    // vertices, or -1 on error (C++ DecodeConnectivity(num_symbols)).
    private decodeConnectivitySymbols(numSymbols: i32): i32 {
        let cornerTable = this.cornerTable!;
        // Active edges (identified by their opposite corners) form a stack:
        // TOPOLOGY_S removes the top edge, TOPOLOGY_E adds a new one.
        let activeCornerStack = new IntVector(numSymbols);

        // Active edges added by topology split events, addressed by the
        // decoder symbol id they belong to (-1 = absent).
        let topologySplitActiveCorners = new Int32Array(numSymbols);
        topologySplitActiveCorners.fill(kInvalidCornerIndex);

        // Vertices marked isolated during decoding; only removed when the
        // mesh has no non-position connectivity data.
        let invalidVertices = new IntVector();
        let removeInvalidVertices = this.attributeData.length == 0;

        // Scratch for isTopologySplit outputs.
        let splitOut = new Int32Array(2);

        let maxNumVertices = this.isVertHole.length;
        let numFaces = 0;
        for (let symbolId = 0; symbolId < numSymbols; symbolId++) {
            let face = numFaces++;
            // Flag cases needing a topology split event check.
            let checkTopologySplit = false;
            let symbol = <i32>this.traversalDecoder.decodeSymbol();
            if (symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_C) {
                // Create a new face between two edges on the open boundary.
                // The first edge is opposite to corner "a" on the top of the
                // active stack; the other is opposite to corner "b" reached
                // through a CCW traversal around the vertex "v".
                //
                //     *-------*
                //    / \     / \
                //   /   \   /   \
                //  /     \ /     \
                // *-------v-------*
                //  \b    /x\    a/
                //   \   /   \   /
                //    \ /  C  \ /
                //     *.......*
                if (activeCornerStack.size() == 0) {
                    return -1;
                }

                let cornerA = activeCornerStack.back();
                let vertexX = cornerTable.vertex(cornerTable.next(cornerA));
                let cornerB = cornerTable.next(cornerTable.leftMostCorner(vertexX));

                if (cornerA == cornerB) {
                    // All matched corners must be different.
                    return -1;
                }
                if (cornerTable.opposite(cornerA) != kInvalidCornerIndex ||
                    cornerTable.opposite(cornerB) != kInvalidCornerIndex) {
                    // One of the corners is already opposite to an existing
                    // face; tampered input.
                    return -1;
                }

                // New tip corner.
                let corner = 3 * face;
                cornerTable.setOppositeCorners(cornerA, corner + 1);
                cornerTable.setOppositeCorners(cornerB, corner + 2);

                // Update vertex mapping.
                let vertAPrev = cornerTable.vertex(cornerTable.previous(cornerA));
                let vertBNext = cornerTable.vertex(cornerTable.next(cornerB));
                if (vertexX == vertAPrev || vertexX == vertBNext) {
                    // Encoding is invalid: face vertices are degenerate.
                    return -1;
                }
                cornerTable.mapCornerToVertex(corner, vertexX);
                cornerTable.mapCornerToVertex(corner + 1, vertBNext);
                cornerTable.mapCornerToVertex(corner + 2, vertAPrev);
                cornerTable.setLeftMostCorner(vertAPrev, corner + 2);
                // Vertex |x| is now interior.
                unchecked(this.isVertHole[vertexX] = 0);
                activeCornerStack.setBack(corner);
            } else if (symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_R ||
                       symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_L) {
                // Create a new face extending from the open boundary edge
                // opposite corner "a"; new boundary edges open opposite the
                // corners "r" and "l", and a new vertex is created opposite
                // corner "a".
                //     *-------*
                //    /a\     / \
                //   /   \   /   \
                //  /     \ /     \
                // *-------v-------*
                //  .l   r.
                //   .   .
                //    . .
                //     *
                if (activeCornerStack.size() == 0) {
                    return -1;
                }
                let cornerA = activeCornerStack.back();
                if (cornerTable.opposite(cornerA) != kInvalidCornerIndex) {
                    // Tampered input.
                    return -1;
                }

                // First corner on the new face is either "l" or "r".
                let corner = 3 * face;
                let oppCorner: i32, cornerL: i32, cornerR: i32;
                if (symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_R) {
                    // "r" is the new first corner.
                    oppCorner = corner + 2;
                    cornerL = corner + 1;
                    cornerR = corner;
                } else {
                    // "l" is the new first corner.
                    oppCorner = corner + 1;
                    cornerL = corner;
                    cornerR = corner + 2;
                }
                cornerTable.setOppositeCorners(oppCorner, cornerA);
                let newVertIndex = cornerTable.addNewVertex();

                if (cornerTable.numVertices() > maxNumVertices) {
                    return -1; // Unexpected number of decoded vertices.
                }

                cornerTable.mapCornerToVertex(oppCorner, newVertIndex);
                cornerTable.setLeftMostCorner(newVertIndex, oppCorner);

                let vertexR = cornerTable.vertex(cornerTable.previous(cornerA));
                cornerTable.mapCornerToVertex(cornerR, vertexR);
                // The new left-most corner of the vertex on |cornerR|.
                cornerTable.setLeftMostCorner(vertexR, cornerR);

                cornerTable.mapCornerToVertex(
                    cornerL, cornerTable.vertex(cornerTable.next(cornerA)));
                activeCornerStack.setBack(corner);
                checkTopologySplit = true;
            } else if (symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_S) {
                // Merge the two last active edges from the stack into a new
                // face; the vertices at corners "p" and "n" merge into one.
                //
                // *-------v-------*
                //  \a   p/x\n   b/
                //   \   /   \   /
                //    \ /  S  \ /
                //     *.......*
                if (activeCornerStack.size() == 0) {
                    return -1;
                }
                let cornerB = activeCornerStack.back();
                activeCornerStack.popBack();

                // Corner "a" can be a normal active edge or one created by a
                // topology split event.
                let splitCorner = unchecked(topologySplitActiveCorners[symbolId]);
                if (splitCorner != kInvalidCornerIndex) {
                    // Topology split event: move the retrieved edge to the
                    // stack.
                    activeCornerStack.push(splitCorner);
                }
                if (activeCornerStack.size() == 0) {
                    return -1;
                }
                let cornerA = activeCornerStack.back();

                if (cornerA == cornerB) {
                    // All matched corners must be different.
                    return -1;
                }
                if (cornerTable.opposite(cornerA) != kInvalidCornerIndex ||
                    cornerTable.opposite(cornerB) != kInvalidCornerIndex) {
                    // Tampered input.
                    return -1;
                }

                // First corner on the new face is corner "x".
                let corner = 3 * face;
                cornerTable.setOppositeCorners(cornerA, corner + 2);
                cornerTable.setOppositeCorners(cornerB, corner + 1);
                // The vertex at corner "x" reuses the vertex of corner "p".
                let vertexP = cornerTable.vertex(cornerTable.previous(cornerA));
                cornerTable.mapCornerToVertex(corner, vertexP);
                cornerTable.mapCornerToVertex(
                    corner + 1, cornerTable.vertex(cornerTable.next(cornerA)));
                let vertBPrev = cornerTable.vertex(cornerTable.previous(cornerB));
                cornerTable.mapCornerToVertex(corner + 2, vertBPrev);
                cornerTable.setLeftMostCorner(vertBPrev, corner + 2);
                let cornerN = cornerTable.next(cornerB);
                let vertexN = cornerTable.vertex(cornerN);
                this.traversalDecoder.mergeVertices(vertexP, vertexN);
                // The new left-most corner of the merged vertex.
                cornerTable.setLeftMostCorner(
                    vertexP, cornerTable.leftMostCorner(vertexN));

                // Remap the vertex at corner "n" and all corners connected to
                // it in the CCW direction.
                let firstCorner = cornerN;
                while (cornerN != kInvalidCornerIndex) {
                    cornerTable.mapCornerToVertex(cornerN, vertexP);
                    cornerN = cornerTable.swingLeft(cornerN);
                    if (cornerN == firstCorner) {
                        // Reaching the start again cannot happen for split
                        // symbols.
                        return -1;
                    }
                }
                // The old vertex |n| becomes isolated.
                cornerTable.makeVertexIsolated(vertexN);
                if (removeInvalidVertices) {
                    invalidVertices.push(vertexN);
                }
                activeCornerStack.setBack(corner);
            } else if (symbol == EdgebreakerTopologyBitPattern.TOPOLOGY_E) {
                let corner = 3 * face;
                let firstVertIndex = cornerTable.addNewVertex();
                // Three new vertices at the corners of the new face.
                cornerTable.mapCornerToVertex(corner, firstVertIndex);
                cornerTable.mapCornerToVertex(corner + 1, cornerTable.addNewVertex());
                cornerTable.mapCornerToVertex(corner + 2, cornerTable.addNewVertex());

                if (cornerTable.numVertices() > maxNumVertices) {
                    return -1; // Unexpected number of decoded vertices.
                }

                cornerTable.setLeftMostCorner(firstVertIndex, corner);
                cornerTable.setLeftMostCorner(firstVertIndex + 1, corner + 1);
                cornerTable.setLeftMostCorner(firstVertIndex + 2, corner + 2);
                // The tip corner becomes a new active edge.
                activeCornerStack.push(corner);
                checkTopologySplit = true;
            } else {
                // Error. Unknown symbol decoded.
                return -1;
            }
            // Inform the traversal decoder that a new corner has been reached.
            this.traversalDecoder.newActiveCornerReached(activeCornerStack.back());

            if (checkTopologySplit) {
                // Only TOPOLOGY_L, TOPOLOGY_R and TOPOLOGY_E faces can be
                // connected to a TOPOLOGY_S face through a topology split
                // event; a detected split adds a new active edge for the
                // corresponding TOPOLOGY_S symbol.

                // Symbol id used by the encoder (reverse).
                let encoderSymbolId = numSymbols - symbolId - 1;
                while (this.isTopologySplit(encoderSymbolId, splitOut)) {
                    let encoderSplitSymbolId = splitOut[1];
                    if (encoderSplitSymbolId < 0) {
                        return -1; // Wrong split symbol id.
                    }
                    // The current symbol has one active edge and two inactive
                    // edges attached to it.
                    //              *
                    //             / \
                    //  left_edge /   \ right_edge
                    //           /     \
                    //          *.......*
                    //         active_edge
                    let actTopCorner = activeCornerStack.back();
                    let newActiveCorner: i32;
                    if (splitOut[0] == EdgeFaceName.RIGHT_FACE_EDGE) {
                        newActiveCorner = cornerTable.next(actTopCorner);
                    } else {
                        newActiveCorner = cornerTable.previous(actTopCorner);
                    }
                    // Add the new active edge, addressed by the decoder symbol
                    // id of the corresponding split symbol.
                    let decoderSplitSymbolId = numSymbols - encoderSplitSymbolId - 1;
                    unchecked(topologySplitActiveCorners[decoderSplitSymbolId] = newActiveCorner);
                }
            }
        }
        if (cornerTable.numVertices() > maxNumVertices) {
            return -1; // Unexpected number of decoded vertices.
        }
        // Decode start faces and connect them to the faces from the active
        // stack.
        while (activeCornerStack.size() > 0) {
            let corner = activeCornerStack.back();
            activeCornerStack.popBack();
            let interiorFace = this.traversalDecoder.decodeStartFaceConfiguration();
            if (interiorFace) {
                // The start face is interior: find the three corners opposite
                // to it. The first, "a", is the top of the active corner
                // stack; "b" and "c" are the next corners from the left-most
                // corners of vertices "n" and "x".
                //
                //           *-------*
                //          / \     / \
                //         /   \   /   \
                //        /     \ /     \
                //       *-------p-------*
                //      / \a    . .    c/ \
                //     /   \   .   .   /   \
                //    /     \ .  I  . /     \
                //   *-------n.......x------*
                //    \     / \     / \     /
                //     \   /   \   /   \   /
                //      \ /     \b/     \ /
                //       *-------*-------*
                if (numFaces >= cornerTable.numFaces()) {
                    return -1; // More faces than expected.
                }

                let cornerA = corner;
                let vertN = cornerTable.vertex(cornerTable.next(cornerA));
                let cornerB = cornerTable.next(cornerTable.leftMostCorner(vertN));

                let vertX = cornerTable.vertex(cornerTable.next(cornerB));
                let cornerC = cornerTable.next(cornerTable.leftMostCorner(vertX));

                if (corner == cornerB || corner == cornerC || cornerB == cornerC) {
                    // All matched corners must be different.
                    return -1;
                }
                if (cornerTable.opposite(corner) != kInvalidCornerIndex ||
                    cornerTable.opposite(cornerB) != kInvalidCornerIndex ||
                    cornerTable.opposite(cornerC) != kInvalidCornerIndex) {
                    // Tampered input.
                    return -1;
                }

                let vertP = cornerTable.vertex(cornerTable.next(cornerC));

                let face = numFaces++;
                // The first corner of the initial face is opposite to "a".
                let newCorner = 3 * face;
                cornerTable.setOppositeCorners(newCorner, corner);
                cornerTable.setOppositeCorners(newCorner + 1, cornerB);
                cornerTable.setOppositeCorners(newCorner + 2, cornerC);

                // Map new corners to existing vertices.
                cornerTable.mapCornerToVertex(newCorner, vertX);
                cornerTable.mapCornerToVertex(newCorner + 1, vertP);
                cornerTable.mapCornerToVertex(newCorner + 2, vertN);

                // All three vertices are interior.
                for (let ci = 0; ci < 3; ci++) {
                    unchecked(this.isVertHole[cornerTable.vertex(newCorner + ci)] = 0);
                }

                this.initFaceConfigurations.push(1);
                this.initCorners.push(newCorner);
            } else {
                // The traversal started from an open boundary; no new face is
                // added, but the first opposite corner is recorded.
                this.initFaceConfigurations.push(0);
                this.initCorners.push(corner);
            }
        }
        if (numFaces != cornerTable.numFaces()) {
            return -1; // Unexpected number of decoded faces.
        }

        let numVertices = cornerTable.numVertices();
        // Remove vertices marked as isolated so that all vertices in range
        // <0, numVertices> are valid.
        for (let i = 0; i < invalidVertices.size(); i++) {
            let invalidVert = invalidVertices.get(i);
            // Find the last valid vertex and swap it with the isolated one.
            let srcVert = numVertices - 1;
            while (cornerTable.leftMostCorner(srcVert) == kInvalidCornerIndex) {
                // The last vertex is invalid; proceed to the previous one.
                srcVert = --numVertices - 1;
            }
            if (srcVert < invalidVert) {
                continue; // No need to swap.
            }

            // Remap all corners of |srcVert| to |invalidVert|.
            let vcit = VertexCornersIterator.fromVertex(cornerTable, srcVert);
            while (!vcit.end()) {
                let cid = vcit.corner();
                if (cornerTable.vertex(cid) != srcVert) {
                    // Corrupted data.
                    return -1;
                }
                cornerTable.mapCornerToVertex(cid, invalidVert);
                vcit.next();
            }
            cornerTable.setLeftMostCorner(
                invalidVert, cornerTable.leftMostCorner(srcVert));

            // Make |srcVert| invalid.
            cornerTable.makeVertexIsolated(srcVert);
            unchecked(this.isVertHole[invalidVert] = this.isVertHole[srcVert]);
            unchecked(this.isVertHole[srcVert] = 0);

            // The last vertex is now invalid.
            numVertices--;
        }
        return numVertices;
    }

    // Decodes all non-position attribute connectivity on the given face.
    private decodeAttributeConnectivitiesOnFace(corner: i32): bool {
        let cornerTable = this.cornerTable!;
        let srcFaceId = cornerTable.face(corner);
        // Three corners of the face.
        for (let c = 0; c < 3; c++) {
            let currentCorner = c == 0
                ? corner
                : (c == 1 ? cornerTable.next(corner) : cornerTable.previous(corner));
            let oppCorner = cornerTable.opposite(currentCorner);
            if (oppCorner == kInvalidCornerIndex) {
                // Boundary edges are always attribute seams; nothing encoded.
                for (let i = 0; i < this.attributeData.length; i++) {
                    this.attributeData[i].attributeSeamCorners.push(currentCorner);
                }
                continue;
            }
            let oppFaceId = cornerTable.face(oppCorner);
            // Don't decode edges when the opposite face was already processed.
            if (oppFaceId < srcFaceId) {
                continue;
            }

            for (let i = 0; i < this.attributeData.length; i++) {
                let isSeam = this.traversalDecoder.decodeAttributeSeam(i);
                if (isSeam) {
                    this.attributeData[i].attributeSeamCorners.push(currentCorner);
                }
            }
        }
        return true;
    }

    // Initializes the mapping between corners and point ids.
    private assignPointsToCorners(numConnectivityVerts: i32): bool {
        // At this point there is one point id for each corner of the mesh.
        let cornerTable = this.cornerTable!;
        let mesh = this.decoder!.mesh();
        mesh.setNumFaces(cornerTable.numFaces());

        if (this.attributeData.length == 0) {
            // Connectivity for positions only: vertex indices are point
            // indices.
            let numFaces = mesh.numFaces();
            for (let f = 0; f < numFaces; f++) {
                let startCorner = 3 * f;
                mesh.setFace(
                    f,
                    cornerTable.vertex(startCorner),
                    cornerTable.vertex(startCorner + 1),
                    cornerTable.vertex(startCorner + 2));
            }
            mesh.setNumPoints(numConnectivityVerts);
            return true;
        }
        // Else multiple attributes need deduplication.

        // One corner per point id, used to sample the attribute values in the
        // last stage of deduplication.
        let pointToCornerMap = new IntVector(cornerTable.numCorners());
        // New point id for every corner.
        let cornerToPointMap = new Int32Array(cornerTable.numCorners());
        let numVertices = cornerTable.numVertices();
        for (let v = 0; v < numVertices; v++) {
            let c = cornerTable.leftMostCorner(v);
            if (c == kInvalidCornerIndex) {
                continue; // Isolated vertex.
            }
            let deduplicationFirstCorner = c;
            if (unchecked(this.isVertHole[v]) != 0) {
                // A boundary vertex: start deduplication from the left-most
                // corner, which is guaranteed to lie on the boundary.
                deduplicationFirstCorner = c;
            } else {
                // For interior vertices find the first seam of any attribute.
                for (let i = 0; i < this.attributeData.length; i++) {
                    let connectivity = this.attributeData[i].connectivityData;
                    if (!connectivity.isCornerOnSeam(c)) {
                        continue; // No seam for this attribute.
                    }
                    // Else there is at least one seam edge; corners and point
                    // ids are still identity mapped here.
                    let vertId = connectivity.vertex(c);
                    let actC = cornerTable.swingRight(c);
                    let seamFound = false;
                    while (actC != c) {
                        if (actC == kInvalidCornerIndex) {
                            return false;
                        }
                        if (connectivity.vertex(actC) != vertId) {
                            // Attribute seam found.
                            deduplicationFirstCorner = actC;
                            seamFound = true;
                            break;
                        }
                        actC = cornerTable.swingRight(actC);
                    }
                    if (seamFound) {
                        break; // A seam was found; other attributes don't matter.
                    }
                }
            }

            // Deduplication pass over the corners of the processed vertex: a
            // single clockwise pass that adds a new point id whenever one of
            // the attributes changes.
            let c2 = deduplicationFirstCorner;
            unchecked(cornerToPointMap[c2] = pointToCornerMap.size());
            pointToCornerMap.push(c2);
            let prevC = c2;
            c2 = cornerTable.swingRight(c2);
            while (c2 != kInvalidCornerIndex && c2 != deduplicationFirstCorner) {
                let attributeSeam = false;
                for (let i = 0; i < this.attributeData.length; i++) {
                    let connectivity = this.attributeData[i].connectivityData;
                    if (connectivity.vertex(c2) != connectivity.vertex(prevC)) {
                        // The attribute index changed from the previous
                        // corner; a new point is needed here.
                        attributeSeam = true;
                        break;
                    }
                }
                if (attributeSeam) {
                    unchecked(cornerToPointMap[c2] = pointToCornerMap.size());
                    pointToCornerMap.push(c2);
                } else {
                    unchecked(cornerToPointMap[c2] = unchecked(cornerToPointMap[prevC]));
                }
                prevC = c2;
                c2 = cornerTable.swingRight(c2);
            }
        }
        // Add faces.
        let numFaces = mesh.numFaces();
        for (let f = 0; f < numFaces; f++) {
            // Remap old points to the new ones.
            mesh.setFace(
                f,
                unchecked(cornerToPointMap[3 * f]),
                unchecked(cornerToPointMap[3 * f + 1]),
                unchecked(cornerToPointMap[3 * f + 2]));
        }
        mesh.setNumPoints(pointToCornerMap.size());
        return true;
    }
}
