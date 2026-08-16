// Ported from draco compression/mesh/traverser/max_prediction_degree_traverser.h.
// Traversal guided by prediction degree of destination vertices, following
// "Multi-way Geometry Encoding" by Cohen-or et al.'02.

import { kInvalidCornerIndex, kInvalidFaceIndex } from "./CornerTable";
import { TraverserBase } from "./TraverserBase";
import { IntVector } from "./IntVector";

const kMaxPriority: i32 = 3;

export class MaxPredictionDegreeTraverser extends TraverserBase {
    // Bucketed stacks of available corners, one per priority.
    private traversalStacks: StaticArray<IntVector> = [new IntVector(), new IntVector(), new IntVector()];
    private bestPriority: i32 = 0;
    private predictionDegree: Int32Array = new Int32Array(0);

    onTraversalStart(): void {
        this.predictionDegree = new Int32Array(this.cornerTable().numVertices());
    }

    traverseFromCorner(cornerId: i32): bool {
        if (this.predictionDegree.length == 0) {
            return true;
        }

        let table = this.cornerTable();
        let observer = this.observer();

        // Traversal starts from |cornerId| and follows the right or left
        // neighboring faces based on their prediction degree.
        this.traversalStacks[0].push(cornerId);
        this.bestPriority = 0;
        // For the first face, check the remaining corners as they may not be
        // processed yet.
        let nextVert = table.vertex(table.next(cornerId));
        let prevVert = table.vertex(table.previous(cornerId));
        if (!this.isVertexVisited(nextVert)) {
            this.markVertexVisited(nextVert);
            observer.onNewVertexVisited(nextVert, table.next(cornerId));
        }
        if (!this.isVertexVisited(prevVert)) {
            this.markVertexVisited(prevVert);
            observer.onNewVertexVisited(prevVert, table.previous(cornerId));
        }
        let tipVertex = table.vertex(cornerId);
        if (!this.isVertexVisited(tipVertex)) {
            this.markVertexVisited(tipVertex);
            observer.onNewVertexVisited(tipVertex, cornerId);
        }
        // Start the actual traversal.
        while ((cornerId = this.popNextCornerToTraverse()) != kInvalidCornerIndex) {
            let faceId = cornerId / 3;
            if (this.isFaceVisited(faceId)) {
                continue;
            }

            while (true) {
                faceId = cornerId / 3;
                this.markFaceVisited(faceId);
                observer.onNewFaceVisited(faceId);

                let vertId = table.vertex(cornerId);
                if (!this.isVertexVisited(vertId)) {
                    this.markVertexVisited(vertId);
                    observer.onNewVertexVisited(vertId, cornerId);
                }

                // Check whether we can traverse to the right and left
                // neighboring faces.
                let rightCornerId = table.getRightCorner(cornerId);
                let leftCornerId = table.getLeftCorner(cornerId);
                let rightFaceId = rightCornerId == kInvalidCornerIndex
                    ? kInvalidFaceIndex
                    : rightCornerId / 3;
                let leftFaceId = leftCornerId == kInvalidCornerIndex
                    ? kInvalidFaceIndex
                    : leftCornerId / 3;
                let isRightFaceVisited = this.isFaceVisited(rightFaceId);
                let isLeftFaceVisited = this.isFaceVisited(leftFaceId);

                if (!isLeftFaceVisited) {
                    let priority = this.computePriority(leftCornerId);
                    if (isRightFaceVisited && priority <= this.bestPriority) {
                        // The left face would be traversed next anyway; no
                        // need to put it onto the stack.
                        cornerId = leftCornerId;
                        continue;
                    } else {
                        this.addCornerToTraversalStack(leftCornerId, priority);
                    }
                }
                if (!isRightFaceVisited) {
                    let priority = this.computePriority(rightCornerId);
                    if (priority <= this.bestPriority) {
                        // The right face would be traversed next anyway.
                        cornerId = rightCornerId;
                        continue;
                    } else {
                        this.addCornerToTraversalStack(rightCornerId, priority);
                    }
                }

                // Couldn't proceed directly to the next corner.
                break;
            }
        }
        return true;
    }

    // Next available corner (edge) to traverse, by priority;
    // kInvalidCornerIndex when no edge is available.
    private popNextCornerToTraverse(): i32 {
        for (let i = this.bestPriority; i < kMaxPriority; i++) {
            let stack = this.traversalStacks[i];
            if (stack.size() > 0) {
                let ret = stack.back();
                stack.popBack();
                this.bestPriority = i;
                return ret;
            }
        }
        return kInvalidCornerIndex;
    }

    private addCornerToTraversalStack(ci: i32, priority: i32): void {
        this.traversalStacks[priority].push(ci);
        if (priority < this.bestPriority) {
            this.bestPriority = priority;
        }
    }

    // Priority of traversing the edge leading to |cornerId|.
    private computePriority(cornerId: i32): i32 {
        let vTip = this.cornerTable().vertex(cornerId);
        // Priority 0 when traversing to already visited vertices.
        let priority = 0;
        if (!this.isVertexVisited(vTip)) {
            let degree = this.predictionDegree[vTip] + 1;
            this.predictionDegree[vTip] = degree;
            // Priority 1 when prediction degree > 1, otherwise 2.
            priority = degree > 1 ? 1 : 2;
        }
        if (priority >= kMaxPriority) {
            priority = kMaxPriority - 1;
        }
        return priority;
    }
}
