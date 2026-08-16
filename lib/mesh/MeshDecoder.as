// Ported from draco compression/mesh/mesh_decoder.h/.cc. Extends
// PointCloudDecoder; the geometry is the same Mesh the host already exposes.

import { EncodedGeometryType } from "../config/CompressionShared";
import { Status } from "../core/Status";
import { DecoderBuffer } from "../core/DecoderBuffer";
import { DecoderOptions } from "../config/DecoderOptions";
import { Mesh } from "./Mesh";
import { PointCloudDecoder } from "../point_cloud/PointCloudDecoder";

export class MeshDecoder extends PointCloudDecoder {
    getGeometryType(): i32 {
        return EncodedGeometryType.TRIANGULAR_MESH;
    }

    decodeMesh(options: DecoderOptions, inBuffer: DecoderBuffer, outMesh: Mesh): Status {
        return this.decode(options, inBuffer, outMesh);
    }

    // pointCloud() and mesh() are the same object; mesh() comes from the host.
    mesh(): Mesh {
        return this.pointCloud();
    }

    decodeGeometryData(): bool {
        if (this.pointCloud_ == null) {
            return false;
        }
        if (!this.decodeConnectivity()) {
            return false;
        }
        return super.decodeGeometryData();
    }

    // Overridden by derived classes.
    decodeConnectivity(): bool {
        return false;
    }
}
