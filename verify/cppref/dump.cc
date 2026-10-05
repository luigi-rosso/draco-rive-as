// Decodes a .drc with canonical draco and writes every attribute's raw values
// in point order, the reference the AS decode must match byte for byte.
// Layout (little endian u32 unless noted): numPoints, numFaces, numAttributes,
// faces[numFaces * 3], then per attribute: uniqueId, type, dataType,
// numComponents, normalized, byteLength, raw bytes.
#include "draco/compression/decode.h"
#include "draco/core/decoder_buffer.h"
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

static void put(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: dump <in.drc> <out.bin>\n");
    return 1;
  }
  std::ifstream in(argv[1], std::ios::binary);
  std::vector<char> data((std::istreambuf_iterator<char>(in)),
                         std::istreambuf_iterator<char>());
  draco::DecoderBuffer buffer;
  buffer.Init(data.data(), data.size());
  draco::Decoder decoder;
  auto status = decoder.DecodeMeshFromBuffer(&buffer);
  if (!status.ok()) {
    fprintf(stderr, "%s: %s\n", argv[1], status.status().error_msg());
    return 1;
  }
  std::unique_ptr<draco::Mesh> mesh = std::move(status).value();
  FILE *f = fopen(argv[2], "wb");
  const uint32_t numPoints = mesh->num_points();
  put(f, numPoints);
  put(f, mesh->num_faces());
  put(f, mesh->num_attributes());
  for (draco::FaceIndex i(0); i < mesh->num_faces(); ++i) {
    for (int c = 0; c < 3; ++c) {
      put(f, mesh->face(i)[c].value());
    }
  }
  for (int a = 0; a < mesh->num_attributes(); ++a) {
    const draco::PointAttribute *att = mesh->attribute(a);
    const uint32_t entry =
        draco::DataTypeLength(att->data_type()) * att->num_components();
    put(f, att->unique_id());
    put(f, att->attribute_type());
    put(f, att->data_type());
    put(f, att->num_components());
    put(f, att->normalized() ? 1 : 0);
    put(f, entry * numPoints);
    for (draco::PointIndex p(0); p < numPoints; ++p) {
      fwrite(att->GetAddress(att->mapped_index(p)), 1, entry, f);
    }
  }
  fclose(f);
  return 0;
}
