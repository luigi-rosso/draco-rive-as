#include "draco/compression/mesh/traverser/depth_first_traverser.h"
#include "draco/compression/mesh/traverser/max_prediction_degree_traverser.h"
#include "draco/mesh/corner_table.h"
#include "draco/mesh/mesh_attribute_corner_table.h"
#include <cstdint>
#include <cstdio>
#include <vector>

using namespace draco;

// Mirrors MeshAttributeIndicesEncodingObserver with point id = Vertex(corner)
// (i.e. mesh faces equal to corner table vertices).
struct RecordingObserver {
  const CornerTable *ct = nullptr;
  std::vector<int> *points = nullptr;
  std::vector<int> *corners = nullptr;
  std::vector<int> *vertexToValue = nullptr;
  int *numValues = nullptr;
  void OnNewFaceVisited(FaceIndex) {}
  inline void OnNewVertexVisited(VertexIndex v, CornerIndex c) {
    points->push_back(ct->Vertex(c).value());
    corners->push_back(c.value());
    (*vertexToValue)[v.value()] = *numValues;
    (*numValues)++;
  }
};

static std::unique_ptr<CornerTable>
makeCT(const std::vector<std::array<VertexIndex, 3>> &faceList) {
  IndexTypeVector<FaceIndex, CornerTable::FaceType> faces;
  for (auto &f : faceList)
    faces.push_back({{f[0], f[1], f[2]}});
  return CornerTable::Create(faces);
}

template <class TraverserT>
static void runTraversal(const char *name, const char *tname,
                         const CornerTable *ct) {
  std::vector<int> points, corners, v2v(ct->num_vertices(), -1);
  int numValues = 0;
  RecordingObserver obs{ct, &points, &corners, &v2v, &numValues};
  TraverserT trav;
  trav.Init(ct, obs);
  trav.OnTraversalStart();
  for (int i = 0; i < ct->num_faces(); ++i) {
    if (!trav.TraverseFromCorner(CornerIndex(3 * i))) {
      printf("TRAV %s %s FAILED\n", name, tname);
      return;
    }
  }
  trav.OnTraversalEnd();
  printf("TRAV %s %s %d", name, tname, (int)points.size());
  for (size_t i = 0; i < points.size(); ++i)
    printf(" %d:%d", points[i], corners[i]);
  for (int v = 0; v < ct->num_vertices(); ++v)
    printf(" v%d", v2v[v]);
  printf("\n");
}

static void runMact(const char *name, const CornerTable *ct,
                    const std::vector<int> &seams) {
  MeshAttributeCornerTable mact;
  mact.InitEmpty(ct);
  for (int s : seams)
    mact.AddSeamEdge(CornerIndex(s));
  if (!mact.RecomputeVertices(nullptr, nullptr)) {
    printf("MACT %s FAILED\n", name);
    return;
  }
  printf("MACT %s %d", name, mact.num_vertices());
  for (int c = 0; c < ct->num_corners(); ++c)
    printf(" %d", mact.Vertex(CornerIndex(c)).value());
  for (int v = 0; v < mact.num_vertices(); ++v)
    printf(" l%d:%d:%d", mact.LeftMostCorner(VertexIndex(v)).value(),
           (int)mact.IsOnBoundary(VertexIndex(v)),
           mact.VertexParent(VertexIndex(v)).value());
  for (int c = 0; c < ct->num_corners(); ++c)
    printf(" o%d", mact.Opposite(CornerIndex(c)).value());
  printf("\n");
}

int main() {
  std::vector<std::pair<const char *, std::vector<std::array<VertexIndex, 3>>>>
      meshes = {
          {"quad",
           {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
            {{VertexIndex(2), VertexIndex(1), VertexIndex(3)}}}},
          {"tetra",
           {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
            {{VertexIndex(0), VertexIndex(3), VertexIndex(1)}},
            {{VertexIndex(0), VertexIndex(2), VertexIndex(3)}},
            {{VertexIndex(1), VertexIndex(3), VertexIndex(2)}}}},
          {"fan",
           {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
            {{VertexIndex(0), VertexIndex(2), VertexIndex(3)}},
            {{VertexIndex(0), VertexIndex(3), VertexIndex(4)}}}},
          {"strip",
           {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
            {{VertexIndex(2), VertexIndex(1), VertexIndex(3)}},
            {{VertexIndex(2), VertexIndex(3), VertexIndex(4)}},
            {{VertexIndex(4), VertexIndex(3), VertexIndex(5)}},
            {{VertexIndex(4), VertexIndex(5), VertexIndex(6)}},
            {{VertexIndex(6), VertexIndex(5), VertexIndex(7)}}}},
      };
  for (auto &m : meshes) {
    auto ct = makeCT(m.second);
    if (!ct) {
      printf("CT %s NULL\n", m.first);
      continue;
    }
    runTraversal<DepthFirstTraverser<CornerTable, RecordingObserver>>(
        m.first, "dfs", ct.get());
    runTraversal<MaxPredictionDegreeTraverser<CornerTable, RecordingObserver>>(
        m.first, "mpd", ct.get());
    runMact(m.first, ct.get(), {});
    // Seams: pick interior edges deterministically (opposite valid, corner <
    // opposite).
    std::vector<int> seams;
    for (int c = 0; c < ct->num_corners(); ++c) {
      CornerIndex o = ct->Opposite(CornerIndex(c));
      if (o != kInvalidCornerIndex && c < o.value() && (c % 2 == 0))
        seams.push_back(c);
    }
    runMact((std::string(m.first) + "_seams").c_str(), ct.get(), seams);
  }
  return 0;
}
