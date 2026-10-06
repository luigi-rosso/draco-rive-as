// Ported from draco compression/mesh/mesh_edgebreaker_traversal_decoder.h.
// Bitstream >= 2.2 only: the DRACO_BACKWARDS_COMPATIBILITY branches are
// dropped (the sample content is 2.2). C++ buffer copy-assignments become
// initView on the source's dataHead, which lands on the same byte.
//
// The C++ template hookup through MeshEdgebreakerDecoderImplInterface is
// replaced by an explicit init(buffer, cornerTable); only the valence decoder
// uses the corner table.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { RAnsBitDecoder } from "../entropy/RAnsBitDecoder";
import { CornerTable } from "./CornerTable";
import { EdgebreakerTopologyBitPattern } from "./MeshEdgebreakerShared";

export class MeshEdgebreakerTraversalDecoder {
    protected buffer: DecoderBuffer = new DecoderBuffer();
    protected symbolBuffer: DecoderBuffer = new DecoderBuffer();
    protected startFaceDecoder: RAnsBitDecoder = new RAnsBitDecoder();
    protected attributeConnectivityDecoders: Array<RAnsBitDecoder> = new Array<RAnsBitDecoder>();
    protected numAttributeData: i32 = 0;

    init(mainBuffer: DecoderBuffer, cornerTable: CornerTable): void {
        this.buffer.initView(mainBuffer.dataHead(), -1, mainBuffer.bitstreamVersion);
    }

    bitstreamVersion(): i32 {
        return this.buffer.bitstreamVersion;
    }

    // The number of vertices expected to be decoded. Ignored by default.
    setNumEncodedVertices(numVertices: i32): void {}

    // Number of non-position attribute data with encoded connectivity.
    setNumAttributeData(numData: i32): void {
        this.numAttributeData = numData;
    }

    // Called before the traversal decoding starts. |outBuffer| is set to the
    // data encoded after the traversal.
    start(outBuffer: DecoderBuffer): bool {
        if (!this.decodeTraversalSymbols()) {
            return false;
        }
        if (!this.decodeStartFaces()) {
            return false;
        }
        if (!this.decodeAttributeSeams()) {
            return false;
        }
        outBuffer.initView(this.buffer.dataHead(), -1, this.buffer.bitstreamVersion);
        return true;
    }

    // The configuration of a new initial face.
    decodeStartFaceConfiguration(): bool {
        return this.startFaceDecoder.decodeNextBit();
    }

    // The next edgebreaker symbol reached during the traversal.
    @inline
    decodeSymbol(): u32 {
        let symbol = this.symbolBuffer.decodeLeastSignificantBits32(1);
        if (symbol == <u32>EdgebreakerTopologyBitPattern.TOPOLOGY_C) {
            return symbol;
        }
        // Else decode two additional bits.
        let symbolSuffix = this.symbolBuffer.decodeLeastSignificantBits32(2);
        return symbol | (symbolSuffix << 1);
    }

    // Called whenever a new active corner is set in the decoder.
    newActiveCornerReached(corner: i32): void {}

    // Called whenever |source| vertex is about to be merged into |dest|.
    mergeVertices(dest: i32, source: i32): void {}

    // True when there is an attribute seam for the next processed pair of
    // visited faces. |attribute| is the non-position attribute id.
    decodeAttributeSeam(attribute: i32): bool {
        return this.attributeConnectivityDecoders[attribute].decodeNextBit();
    }

    // Called when the traversal is finished.
    done(): void {
        if (this.symbolBuffer.bitDecoderActive()) {
            this.symbolBuffer.endBitDecoding();
        }
        this.startFaceDecoder.endDecoding();
    }

    protected decodeTraversalSymbols(): bool {
        // The symbol buffer takes over at the current head; the main buffer
        // then resumes past the size varint and the traversal bytes.
        this.symbolBuffer.initView(this.buffer.dataHead(), -1, this.buffer.bitstreamVersion);
        let traversalSize = this.symbolBuffer.startBitDecoding(true);
        if (this.symbolBuffer.err) {
            return false;
        }
        this.buffer.initView(this.symbolBuffer.dataHead(), -1, this.symbolBuffer.bitstreamVersion);
        if (traversalSize > <u64>this.buffer.remainingSize()) {
            return false;
        }
        this.buffer.advance(<i32>traversalSize);
        return true;
    }

    protected decodeStartFaces(): bool {
        return this.startFaceDecoder.startDecoding(this.buffer);
    }

    protected decodeAttributeSeams(): bool {
        this.attributeConnectivityDecoders = new Array<RAnsBitDecoder>();
        for (let i = 0; i < this.numAttributeData; i++) {
            let decoder = new RAnsBitDecoder();
            if (!decoder.startDecoding(this.buffer)) {
                return false;
            }
            this.attributeConnectivityDecoders.push(decoder);
        }
        return true;
    }
}
