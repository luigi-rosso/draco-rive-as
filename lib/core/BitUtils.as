// Ported from draco.js core/BitUtils.js (bit_utils.h/cc).
//
// Zigzag decode of unsigned symbols back to signed integers.

export unsafe function convertSymbolsToSignedInts(input: Uint32Array, count: i32, output: Int32Array): void {
    let inPtr = input.dataStart;
    let outPtr = output.dataStart;
    for (let i = 0; i < count; i++) {
        let val = load<u32>(inPtr + (<usize>i << 2));
        let half = <i32>(val >> 1);
        store<i32>(outPtr + (<usize>i << 2), (val & 1) == 0 ? half : -half - 1);
    }
}

export function convertSymbolToSignedInt(val: u32): i32 {
    let isPositive = (val & 1) == 0;
    let half = <i32>(val >> 1);
    if (isPositive) {
        return half;
    }
    return -half - 1;
}
