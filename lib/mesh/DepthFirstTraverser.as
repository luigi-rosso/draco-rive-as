// Ported from draco compression/mesh/traverser/depth_first_traverser.h.

import { kInvalidCornerIndex, kInvalidVertexIndex, kInvalidFaceIndex } from "./CornerTable";
import { TraverserBase } from "./TraverserBase";
import { IntVector } from "./IntVector";

export class DepthFirstTraverser extends TraverserBase {
    private cornerTraversalStack: IntVector = new IntVector();

    traverseFromCorner(cornerId: i32): bool {
        if (this.isFaceOfCornerVisited(cornerId)) {
            return true; // Already traversed.
        }

        let table = this.cornerTable();
        let observer = this.observer();

        this.cornerTraversalStack.clear();
        this.cornerTraversalStack.reserve(table.numFaces());
        this.cornerTraversalStack.push(cornerId);
        // For the first face, check the remaining corners as they may not be
        // processed yet.
        let nextVert = table.vertex(table.next(cornerId));
        let prevVert = table.vertex(table.previous(cornerId));
        if (nextVert == kInvalidVertexIndex || prevVert == kInvalidVertexIndex) {
            return false;
        }
        if (!this.isVertexVisited(nextVert)) {
            this.markVertexVisited(nextVert);
            observer.onNewVertexVisited(nextVert, table.next(cornerId));
        }
        if (!this.isVertexVisited(prevVert)) {
            this.markVertexVisited(prevVert);
            observer.onNewVertexVisited(prevVert, table.previous(cornerId));
        }

        // Start the actual traversal.
        while (this.cornerTraversalStack.size() > 0) {
            // Currently processed corner.
            cornerId = this.cornerTraversalStack.back();
            let faceId = cornerId / 3;
            // Make sure the face hasn't been visited yet.
            if (cornerId == kInvalidCornerIndex || this.isFaceVisited(faceId)) {
                this.cornerTraversalStack.popBack();
                continue;
            }
            while (true) {
                this.markFaceVisited(faceId);
                let vertId = table.vertex(cornerId);
                if (vertId == kInvalidVertexIndex) {
                    return false;
                }
                if (!this.isVertexVisited(vertId)) {
                    let onBoundary = table.isOnBoundary(vertId);
                    this.markVertexVisited(vertId);
                    observer.onNewVertexVisited(vertId, cornerId);
                    if (!onBoundary) {
                        cornerId = table.getRightCorner(cornerId);
                        faceId = cornerId / 3;
                        continue;
                    }
                }
                // The current vertex has been visited before or lies on a
                // boundary; try to visit one of the neighboring faces.
                let rightCornerId = table.getRightCorner(cornerId);
                let leftCornerId = table.getLeftCorner(cornerId);
                let rightFaceId = rightCornerId == kInvalidCornerIndex
                    ? kInvalidFaceIndex
                    : rightCornerId / 3;
                let leftFaceId = leftCornerId == kInvalidCornerIndex
                    ? kInvalidFaceIndex
                    : leftCornerId / 3;
                if (this.isFaceVisited(rightFaceId)) {
                    if (this.isFaceVisited(leftFaceId)) {
                        // Both neighboring faces are visited. End reached.
                        this.cornerTraversalStack.popBack();
                        break;
                    } else {
                        // Go to the left face.
                        cornerId = leftCornerId;
                        faceId = leftFaceId;
                    }
                } else {
                    if (this.isFaceVisited(leftFaceId)) {
                        // Left face visited, go to the right one.
                        cornerId = rightCornerId;
                        faceId = rightFaceId;
                    } else {
                        // Split the traversal: the stack top becomes the left
                        // face (processed second), the right face goes on top.
                        this.cornerTraversalStack.setBack(leftCornerId);
                        this.cornerTraversalStack.push(rightCornerId);
                        break;
                    }
                }
            }
        }
        return true;
    }
}
