// Ported from draco compression/mesh/mesh_edgebreaker_shared.h (decoder subset).

// Variable length encoding of the topology configurations reached during the
// surface traversal; roughly half of all configurations are TOPOLOGY_C.
export enum EdgebreakerTopologyBitPattern {
    TOPOLOGY_C = 0x0,
    TOPOLOGY_S = 0x1,
    TOPOLOGY_L = 0x3,
    TOPOLOGY_R = 0x5,
    TOPOLOGY_E = 0x7,
    // Marks the initial face of a connected component; never encoded.
    TOPOLOGY_INIT_FACE = 8,
    TOPOLOGY_INVALID = 9,
}

export enum EdgebreakerSymbol {
    EDGEBREAKER_SYMBOL_C = 0,
    EDGEBREAKER_SYMBOL_S = 1,
    EDGEBREAKER_SYMBOL_L = 2,
    EDGEBREAKER_SYMBOL_R = 3,
    EDGEBREAKER_SYMBOL_E = 4,
    EDGEBREAKER_SYMBOL_INVALID = 5,
}

function makeTopologyToSymbolId(): Int32Array {
    let t = new Int32Array(8);
    t[0] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_C;
    t[1] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_S;
    t[2] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_INVALID;
    t[3] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_L;
    t[4] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_INVALID;
    t[5] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_R;
    t[6] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_INVALID;
    t[7] = EdgebreakerSymbol.EDGEBREAKER_SYMBOL_E;
    return t;
}

function makeSymbolToTopologyId(): Int32Array {
    let t = new Int32Array(5);
    t[0] = EdgebreakerTopologyBitPattern.TOPOLOGY_C;
    t[1] = EdgebreakerTopologyBitPattern.TOPOLOGY_S;
    t[2] = EdgebreakerTopologyBitPattern.TOPOLOGY_L;
    t[3] = EdgebreakerTopologyBitPattern.TOPOLOGY_R;
    t[4] = EdgebreakerTopologyBitPattern.TOPOLOGY_E;
    return t;
}

// Symbol id (or invalid) for each topology bit pattern.
export const edgeBreakerTopologyToSymbolId: Int32Array = makeTopologyToSymbolId();

// Topology bit pattern for each symbol id.
export const edgeBreakerSymbolToTopologyId: Int32Array = makeSymbolToTopologyId();

// Edge types relative to the tip vertex of a visited triangle.
export enum EdgeFaceName {
    LEFT_FACE_EDGE = 0,
    RIGHT_FACE_EDGE = 1,
}

// Source face connecting to an already traversed face (initial face or
// TOPOLOGY_S); two events per topological handle, one per hole.
export class TopologySplitEventData {
    splitSymbolId: u32 = 0;
    sourceSymbolId: u32 = 0;
    // 0/1, see EdgeFaceName.
    sourceEdge: u32 = 0;
}
