// typed.luau emulated JS typed arrays over Luau buffers; AssemblyScript has
// the real ones, so the port maps straight onto the native classes:
//
//   typed.T.new(n)             -> new T(n)
//   typed.T.new(buf, off, len) -> T.wrap(buf, off, len)
//   typed.T.new(typedArray)    -> typedArrayCopy / slice()
//   typed.T.new({ ... })       -> the fromList helpers below
//   typed.ArrayBuffer(n)       -> new ArrayBuffer(n)
//
// Hot loops that bypassed metamethods via typed.T.read/write map onto
// load<T>/store<T> at view.dataStart.

export function uint8FromList(values: Array<u8>): Uint8Array {
    let out = new Uint8Array(values.length);
    for (let i = 0; i < values.length; i++) {
        out[i] = values[i];
    }
    return out;
}

export function uint16FromList(values: Array<u16>): Uint16Array {
    let out = new Uint16Array(values.length);
    for (let i = 0; i < values.length; i++) {
        out[i] = values[i];
    }
    return out;
}

export function int32FromList(values: Array<i32>): Int32Array {
    let out = new Int32Array(values.length);
    for (let i = 0; i < values.length; i++) {
        out[i] = values[i];
    }
    return out;
}

export function uint32FromList(values: Array<u32>): Uint32Array {
    let out = new Uint32Array(values.length);
    for (let i = 0; i < values.length; i++) {
        out[i] = values[i];
    }
    return out;
}

export function float32FromList(values: Array<f32>): Float32Array {
    let out = new Float32Array(values.length);
    for (let i = 0; i < values.length; i++) {
        out[i] = values[i];
    }
    return out;
}
