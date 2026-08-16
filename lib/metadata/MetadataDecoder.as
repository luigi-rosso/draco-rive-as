// Minimal stand-in for draco.js metadata/MetadataDecoder.js. Our sample
// assets carry no metadata (the METADATA flag is unset), so
// skipGeometryMetadata is never reached. Returning false makes a
// metadata-bearing file fail loudly rather than mis-decode. TODO: port real
// metadata skipping if needed.

import { DecoderBuffer } from "../core/DecoderBuffer";

export class MetadataDecoder {
    skipGeometryMetadata(buffer: DecoderBuffer): bool {
        return false;
    }
}
