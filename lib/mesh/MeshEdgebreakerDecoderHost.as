// Phase C seam replacing draco's MeshEdgebreakerDecoder: the impl pulls the
// main buffer and mesh from here and hands finished sequencers back through
// setAttributesDecoder (C++ wraps them in a
// SequentialAttributeDecodersController there).

import { DecoderBuffer } from "../core/DecoderBuffer";
import { PointsSequencer } from "../attributes/PointsSequencer";
import { Mesh } from "./Mesh";

export abstract class MeshEdgebreakerDecoderHost {
    private _buffer: DecoderBuffer = new DecoderBuffer();
    private _mesh: Mesh = new Mesh();

    buffer(): DecoderBuffer {
        return this._buffer;
    }

    mesh(): Mesh {
        return this._mesh;
    }

    // Attribute decoder registry, filled by phase C's decoder while my
    // createAttributesDecoder runs; queried by getAttribute*Data.
    numAttributesDecoders(): i32 {
        return 0;
    }

    attributesDecoderNumAttributes(decoderId: i32): i32 {
        return 0;
    }

    attributesDecoderAttributeId(decoderId: i32, j: i32): i32 {
        return -1;
    }

    // True when header counts pass the decoder options' size limits.
    exceedsLimits(numPoints: u32, numFaces: u32): bool {
        return false;
    }

    // Receives the sequencer for one attributes decoder slot.
    setAttributesDecoder(attDecoderId: i32, sequencer: PointsSequencer): bool {
        return false;
    }
}
