// Ported from draco.js compression/attributes/NormalCompressionUtils.js
// (compression/attributes/normal_compression_utils.h) via the Luau port.
// Converts unit vectors to/from octahedral coordinates for normal compression.
// All decode math is float32 (the Luau frounded every step); AS f32 arithmetic
// rounds identically, so the chains become plain f32 expressions.

export class OctahedronToolBox {
    _quantizationBits: i32 = -1;
    _maxQuantizedValue: i32 = -1;
    _maxValue: i32 = -1;
    _dequantizationScale: f32 = 1.0;
    _centerValue: i32 = -1;

    // q: quantization bits, valid range 2..30.
    setQuantizationBits(q: i32): bool {
        if (q < 2 || q > 30) {
            return false;
        }
        this._quantizationBits = q;
        this._maxQuantizedValue = (1 << q) - 1;
        this._maxValue = this._maxQuantizedValue - 1;
        this._dequantizationScale = <f32>2.0 / <f32>this._maxValue;
        this._centerValue = this._maxValue / 2;
        return true;
    }

    isInitialized(): bool {
        return this._quantizationBits != -1;
    }

    quantizationBits(): i32 {
        return this._quantizationBits;
    }

    // Canonicalizes edge points into consistent quadrants. Writes out[0], out[1].
    canonicalizeOctahedralCoords(s: i32, t: i32, out: Int32Array): void {
        let maxValue = this._maxValue;
        let centerValue = this._centerValue;
        if ((s == 0 && t == 0) || (s == 0 && t == maxValue) || (s == maxValue && t == 0)) {
            s = maxValue;
            t = maxValue;
        } else if (s == 0 && t > centerValue) {
            t = centerValue - (t - centerValue);
        } else if (s == maxValue && t < centerValue) {
            t = centerValue + (centerValue - t);
        } else if (t == maxValue && s < centerValue) {
            s = centerValue + (centerValue - s);
        } else if (t == 0 && s > centerValue) {
            s = centerValue - (s - centerValue);
        }
        out[0] = s;
        out[1] = t;
    }

    // Precondition: abs sum of intVec ([x,y,z]) equals centerValue.
    integerVectorToQuantizedOctahedralCoords(intVec: Int32Array, out: Int32Array): void {
        let centerValue = this._centerValue;
        let maxValue = this._maxValue;
        let s: i32;
        let t: i32;
        if (intVec[0] >= 0) {
            s = intVec[1] + centerValue;
            t = intVec[2] + centerValue;
        } else {
            if (intVec[1] < 0) {
                s = abs(intVec[2]);
            } else {
                s = maxValue - abs(intVec[2]);
            }
            if (intVec[2] < 0) {
                t = abs(intVec[1]);
            } else {
                t = maxValue - abs(intVec[1]);
            }
        }
        this.canonicalizeOctahedralCoords(s, t, out);
    }

    // Normalizes vec ([x,y,z], modified in place) so its abs sum equals
    // centerValue. The scaling products can exceed i32, so they stay f64 like
    // the Luau's double math.
    canonicalizeIntegerVector(vec: Int32Array): void {
        let centerValue = this._centerValue;
        let absSum = <f64>abs(vec[0]) + <f64>abs(vec[1]) + <f64>abs(vec[2]);
        if (absSum == 0) {
            vec[0] = centerValue;
            // vec[1] and vec[2] remain 0.
        } else {
            vec[0] = <i32>Math.trunc(<f64>vec[0] * <f64>centerValue / absSum);
            vec[1] = <i32>Math.trunc(<f64>vec[1] * <f64>centerValue / absSum);
            if (vec[2] >= 0) {
                vec[2] = centerValue - abs(vec[0]) - abs(vec[1]);
            } else {
                vec[2] = -(centerValue - abs(vec[0]) - abs(vec[1]));
            }
        }
    }

    maxQuantizedValue(): i32 {
        return this._maxQuantizedValue;
    }

    maxValue(): i32 {
        return this._maxValue;
    }

    centerValue(): i32 {
        return this._centerValue;
    }

    // Phase B additions ported from C++ normal_compression_utils.h: the
    // diamond/mod helpers the octahedral prediction transforms use. All expect
    // coordinates already centered at the origin.

    isInDiamond(s: i32, t: i32): bool {
        // Unsigned add so |s| + |t| cannot overflow on bad data.
        let st = <u32>abs(s) + <u32>abs(t);
        return st <= <u32>this._centerValue;
    }

    // Writes the inverted point to out[0], out[1].
    invertDiamond(s: i32, t: i32, out: Int32Array): void {
        let signS = 0;
        let signT = 0;
        if (s >= 0 && t >= 0) {
            signS = 1;
            signT = 1;
        } else if (s <= 0 && t <= 0) {
            signS = -1;
            signT = -1;
        } else {
            signS = s > 0 ? 1 : -1;
            signT = t > 0 ? 1 : -1;
        }

        // Additions and subtractions in unsigned to avoid signed overflow on
        // bad data; results match for the non-overflowing cases.
        let cornerPointS = <u32>(signS * this._centerValue);
        let cornerPointT = <u32>(signT * this._centerValue);
        let us = <u32>s;
        let ut = <u32>t;
        us = us + us - cornerPointS;
        ut = ut + ut - cornerPointT;
        if (signS * signT >= 0) {
            let temp = us;
            us = <u32>0 - ut;
            ut = <u32>0 - temp;
        } else {
            let temp = us;
            us = ut;
            ut = temp;
        }
        us = us + cornerPointS;
        ut = ut + cornerPointT;

        // The final divide is signed (truncating), matching the C++ int32 /=.
        out[0] = <i32>us / 2;
        out[1] = <i32>ut / 2;
    }

    invertDirection(s: i32, t: i32, out: Int32Array): void {
        this.invertDiamond(-s, -t, out);
    }

    // For correction values.
    modMax(x: i32): i32 {
        if (x > this._centerValue) {
            return x - this._maxQuantizedValue;
        }
        if (x < -this._centerValue) {
            return x + this._maxQuantizedValue;
        }
        return x;
    }

    // For correction values.
    makePositive(x: i32): i32 {
        if (x < 0) {
            return x + this._maxQuantizedValue;
        }
        return x;
    }

    quantizedOctahedralCoordsToUnitVector(inS: i32, inT: i32, outVector: Float32Array): void {
        let scale = this._dequantizationScale;
        this.octahedralCoordsToUnitVector(
            <f32>inS * scale - <f32>1.0, <f32>inT * scale - <f32>1.0, outVector);
    }

    octahedralCoordsToUnitVector(inSScaled: f32, inTScaled: f32, outVector: Float32Array): void {
        let y = inSScaled;
        let z = inTScaled;
        let x: f32 = (<f32>1.0 - Mathf.abs(y)) - Mathf.abs(z);

        let xOffset: f32 = -x;
        if (xOffset < 0) {
            xOffset = 0;
        }

        y += y < 0 ? xOffset : -xOffset;
        z += z < 0 ? xOffset : -xOffset;

        let normSquared: f32 = x * x + y * y + z * z;
        if (normSquared < <f32>1e-6) {
            unchecked(outVector[0] = 0);
            unchecked(outVector[1] = 0);
            unchecked(outVector[2] = 0);
        } else {
            let d: f32 = <f32>1.0 / Mathf.sqrt(normSquared);
            unchecked(outVector[0] = x * d);
            unchecked(outVector[1] = y * d);
            unchecked(outVector[2] = z * d);
        }
    }
}
