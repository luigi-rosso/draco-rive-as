// Base for point-id sequencers (draco compression/attributes/points_sequencer).
// The Luau duck-typed this contract between LinearSequencer and
// MeshTraversalSequencer; AS needs a nominal base so the attributes controller
// can hold either. generateSequence drops the Luau's unused out param: callers
// read the result via getOutputPointIds.

import { PointAttribute } from "./PointAttribute";

export abstract class PointsSequencer {
    generateSequence(): bool {
        return false;
    }

    getOutputPointIds(): Int32Array {
        return new Int32Array(0);
    }

    updatePointToAttributeIndexMapping(attribute: PointAttribute): bool {
        return false;
    }

    // Only meaningful for traversal-driven sequencers.
    addPointId(pointId: i32): void {}
}
