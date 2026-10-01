// Ported from draco compression/mesh/mesh_edgebreaker_decoder.h/.cc. Thin
// class over phase B's MeshEdgebreakerDecoderImpl: selects the traversal
// decoder from the bitstream and completes the host seam by wrapping finished
// sequencers in a SequentialAttributeDecodersController.

import { MeshEdgebreakerConnectivityEncodingMethod } from "../config/CompressionShared";
import { CornerTable } from "./CornerTable";
import { MeshAttributeCornerTable } from "./MeshAttributeCornerTable";
import { MeshAttributeIndicesEncodingData } from "./MeshAttributeIndicesEncodingData";
import { MeshDecoder } from "./MeshDecoder";
import { MeshEdgebreakerDecoderImpl } from "./MeshEdgebreakerDecoderImpl";
import { MeshEdgebreakerTraversalDecoder } from "./MeshEdgebreakerTraversalDecoder";
import { MeshEdgebreakerTraversalValenceDecoder } from "./MeshEdgebreakerTraversalValenceDecoder";
import { PointsSequencer } from "../attributes/PointsSequencer";
import { SequentialAttributeDecodersController } from "../attributes/SequentialAttributeDecodersController";

export class MeshEdgebreakerDecoder extends MeshDecoder {
    private impl_: MeshEdgebreakerDecoderImpl? = null;

    getCornerTable(): CornerTable? {
        let impl = this.impl_;
        if (impl == null) {
            return null;
        }
        return impl.getCornerTable();
    }

    getAttributeCornerTable(attId: i32): MeshAttributeCornerTable? {
        let impl = this.impl_;
        if (impl == null) {
            return null;
        }
        return impl.getAttributeCornerTable(attId);
    }

    getAttributeEncodingData(attId: i32): MeshAttributeIndicesEncodingData? {
        let impl = this.impl_;
        if (impl == null) {
            return null;
        }
        return impl.getAttributeEncodingData(attId);
    }

    initializeDecoder(): bool {
        let traversalDecoderType = this.buffer().decodeUint8();
        if (this.buffer().err) {
            return false;
        }

        let impl: MeshEdgebreakerDecoderImpl;
        if (traversalDecoderType ==
            <u32>MeshEdgebreakerConnectivityEncodingMethod.MESH_EDGEBREAKER_STANDARD_ENCODING) {
            impl = new MeshEdgebreakerDecoderImpl(new MeshEdgebreakerTraversalDecoder());
        } else if (traversalDecoderType ==
            <u32>MeshEdgebreakerConnectivityEncodingMethod.MESH_EDGEBREAKER_VALENCE_ENCODING) {
            impl = new MeshEdgebreakerDecoderImpl(new MeshEdgebreakerTraversalValenceDecoder());
        } else {
            // MESH_EDGEBREAKER_PREDICTIVE_ENCODING is deprecated pre-2.2.
            return false;
        }
        this.impl_ = impl;
        return impl.init(this);
    }

    createAttributesDecoder(attDecoderId: i32): bool {
        return this.impl_!.createAttributesDecoder(attDecoderId);
    }

    decodeConnectivity(): bool {
        return this.impl_!.decodeConnectivity();
    }

    onAttributesDecoded(): bool {
        return this.impl_!.onAttributesDecoded();
    }

    // Host seam: the impl hands each finished sequencer here; C++ wraps it in
    // a SequentialAttributeDecodersController the same way.
    setAttributesDecoder(attDecoderId: i32, sequencer: PointsSequencer): bool {
        return this.storeAttributesDecoder(
            attDecoderId, new SequentialAttributeDecodersController(sequencer));
    }
}
