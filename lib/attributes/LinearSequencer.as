// Ported from draco compression/attributes/linear_sequencer.h: points keep
// their input order, so every attribute maps identically.

import { PointAttribute } from "./PointAttribute";
import { PointsSequencer } from "./PointsSequencer";

export class LinearSequencer extends PointsSequencer {
    private numPoints: i32;
    private outPointIds: Int32Array = new Int32Array(0);

    constructor(numPoints: i32) {
        super();
        this.numPoints = numPoints;
    }

    generateSequence(): bool {
        if (this.numPoints < 0) {
            return false;
        }
        let ids = new Int32Array(this.numPoints);
        for (let i = 0; i < this.numPoints; i++) {
            unchecked(ids[i] = i);
        }
        this.outPointIds = ids;
        return true;
    }

    getOutputPointIds(): Int32Array {
        return this.outPointIds;
    }

    updatePointToAttributeIndexMapping(attribute: PointAttribute): bool {
        attribute.setIdentityMapping();
        return true;
    }
}
