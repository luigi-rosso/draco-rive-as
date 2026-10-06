// Ported from draco compression/mesh/mesh_edgebreaker_traversal_valence_decoder.h
// (bitstream >= 2.2 subset). Maintains valences of the decoded portion of the
// mesh and picks the entropy context for each symbol from the clamped valence
// of the active vertex.
//
// Deviation from C++: the DecodeSymbols return value is checked (C++ ignores
// it and would decode from a zeroed array on malformed input).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { decodeSymbols } from "../entropy/SymbolDecoding";
import { CornerTable } from "./CornerTable";
import { MeshEdgebreakerTraversalDecoder } from "./MeshEdgebreakerTraversalDecoder";
import {
    EdgebreakerTopologyBitPattern,
    edgeBreakerSymbolToTopologyId,
} from "./MeshEdgebreakerShared";

export class MeshEdgebreakerTraversalValenceDecoder extends MeshEdgebreakerTraversalDecoder {
    private cornerTable: CornerTable? = null;
    private numVertices: i32 = 0;
    private vertexValences: Int32Array = new Int32Array(0);
    private lastSymbol: i32 = -1;
    private activeContext: i32 = -1;

    private minValence: i32 = 2;
    private maxValence: i32 = 7;
    private contextSymbols: Array<Uint32Array> = new Array<Uint32Array>();
    // Points to the active symbol in each context (processed from the back).
    private contextCounters: Int32Array = new Int32Array(0);

    init(mainBuffer: DecoderBuffer, cornerTable: CornerTable): void {
        super.init(mainBuffer, cornerTable);
        this.cornerTable = cornerTable;
    }

    setNumEncodedVertices(numVertices: i32): void {
        this.numVertices = numVertices;
    }

    start(outBuffer: DecoderBuffer): bool {
        if (!this.decodeStartFaces()) {
            return false;
        }
        if (!this.decodeAttributeSeams()) {
            return false;
        }
        outBuffer.initView(this.buffer.dataHead(), -1, this.buffer.bitstreamVersion);

        this.minValence = 2;
        this.maxValence = 7;

        if (this.numVertices < 0) {
            return false;
        }
        // Set the valences of all initial vertices to 0.
        this.vertexValences = new Int32Array(this.numVertices);

        let numUniqueValences = this.maxValence - this.minValence + 1;

        // Decode all symbols for all contexts.
        this.contextSymbols = new Array<Uint32Array>();
        this.contextCounters = new Int32Array(numUniqueValences);
        for (let i = 0; i < numUniqueValences; i++) {
            let numSymbols = outBuffer.decodeVarintUint32();
            if (outBuffer.err) {
                return false;
            }
            if (numSymbols > <u32>this.cornerTable!.numFaces()) {
                return false;
            }
            if (numSymbols > 0) {
                let symbols = new Uint32Array(<i32>numSymbols);
                if (!decodeSymbols(<i32>numSymbols, 1, outBuffer, symbols)) {
                    return false;
                }
                this.contextSymbols.push(symbols);
                this.contextCounters[i] = <i32>numSymbols;
            } else {
                this.contextSymbols.push(new Uint32Array(0));
                this.contextCounters[i] = 0;
            }
        }
        return true;
    }

    @inline
    decodeSymbol(): u32 {
        // First check if we have a valid context.
        if (this.activeContext != -1) {
            let contextCounter = unchecked(this.contextCounters[this.activeContext]) - 1;
            unchecked(this.contextCounters[this.activeContext] = contextCounter);
            if (contextCounter < 0) {
                return <u32>EdgebreakerTopologyBitPattern.TOPOLOGY_INVALID;
            }
            let symbolId = unchecked(this.contextSymbols[this.activeContext][contextCounter]);
            if (symbolId > 4) {
                return <u32>EdgebreakerTopologyBitPattern.TOPOLOGY_INVALID;
            }
            this.lastSymbol = unchecked(edgeBreakerSymbolToTopologyId[symbolId]);
        } else {
            // The first symbol must be E.
            this.lastSymbol = EdgebreakerTopologyBitPattern.TOPOLOGY_E;
        }
        return <u32>this.lastSymbol;
    }

    @inline
    newActiveCornerReached(corner: i32): void {
        let table = this.cornerTable!;
        let next = table.next(corner);
        let prev = table.previous(corner);
        let valences = this.vertexValences;
        let vc = table.vertex(corner);
        let vn = table.vertex(next);
        let vp = table.vertex(prev);
        let sym = this.lastSymbol;
        if (sym == EdgebreakerTopologyBitPattern.TOPOLOGY_C ||
            sym == EdgebreakerTopologyBitPattern.TOPOLOGY_S) {
            unchecked(valences[vn] += 1);
            unchecked(valences[vp] += 1);
        } else if (sym == EdgebreakerTopologyBitPattern.TOPOLOGY_R) {
            unchecked(valences[vc] += 1);
            unchecked(valences[vn] += 1);
            unchecked(valences[vp] += 2);
        } else if (sym == EdgebreakerTopologyBitPattern.TOPOLOGY_L) {
            unchecked(valences[vc] += 1);
            unchecked(valences[vn] += 2);
            unchecked(valences[vp] += 1);
        } else if (sym == EdgebreakerTopologyBitPattern.TOPOLOGY_E) {
            unchecked(valences[vc] += 2);
            unchecked(valences[vn] += 2);
            unchecked(valences[vp] += 2);
        }

        // The clamped valence of the next vertex selects the context for the
        // next symbol.
        let activeValence = unchecked(valences[vn]);
        let clampedValence: i32;
        if (activeValence < this.minValence) {
            clampedValence = this.minValence;
        } else if (activeValence > this.maxValence) {
            clampedValence = this.maxValence;
        } else {
            clampedValence = activeValence;
        }
        this.activeContext = clampedValence - this.minValence;
    }

    mergeVertices(dest: i32, source: i32): void {
        // Update valences on the merged vertices.
        this.vertexValences[dest] += this.vertexValences[source];
    }
}
