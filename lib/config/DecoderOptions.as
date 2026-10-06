// Ported from draco.js compression/config/DecoderOptions.js, plus size limits
// canonical draco lacks.

import { DracoOptions } from "./DracoOptions";

export class DecoderOptions extends DracoOptions {
    // Header counts past these are rejected before anything is sized from
    // them, so untrusted input cannot exhaust wasm memory.
    maxPoints: u32 = 2000000;
    maxFaces: u32 = 4000000;
}
