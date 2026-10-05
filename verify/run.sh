#!/bin/zsh
# Differential verification: compiles the C++ reference generators against the
# canonical draco sources, regenerates the vectors, compiles the AS drivers
# with rasc, and runs the node comparisons. DRACO_BUILD is a cmake build of
# those sources configured with -DCMAKE_CXX_FLAGS=-ffp-contract=off, since
# fused multiply-adds round the normal math differently from wasm.
set -e
cd "$(dirname "$0")"
DRACO_SRC=${DRACO_SRC:-$HOME/Projects/draco/src}
DRACO_BUILD=${DRACO_BUILD:-$HOME/Projects/draco/build}
export RASC=${RASC:-$HOME/Projects/rive/packages/rasc/animascript/out/release/rasc}
export AS_STD=${AS_STD:-$HOME/Projects/rive/packages/rasc/animascript/std}

mkdir -p vectors
clang++ -w -std=c++14 -I "$DRACO_SRC" -I cppref cppref/ref.cc -o cppref/ref
clang++ -w -std=c++14 -I "$DRACO_SRC" -I cppref cppref/ref2.cc "$DRACO_SRC/draco/mesh/corner_table.cc" -o cppref/ref2
clang++ -w -std=c++14 -I "$DRACO_SRC" -I cppref cppref/ref3.cc "$DRACO_SRC/draco/mesh/corner_table.cc" "$DRACO_SRC/draco/mesh/mesh_attribute_corner_table.cc" -o cppref/ref3
clang++ -w -std=c++14 -I "$DRACO_SRC" -I cppref cppref/ref4.cc "$DRACO_SRC/draco/mesh/corner_table.cc" "$DRACO_SRC/draco/attributes/point_attribute.cc" "$DRACO_SRC/draco/attributes/geometry_attribute.cc" "$DRACO_SRC/draco/core/data_buffer.cc" "$DRACO_SRC/draco/core/draco_types.cc" -o cppref/ref4
clang++ -O2 -ffp-contract=off -w -std=c++17 -I "$DRACO_SRC" -I "$DRACO_BUILD" cppref/dump.cc "$DRACO_BUILD/libdraco.a" -o cppref/dump
./cppref/ref > vectors/octa_vectors.txt
./cppref/ref2 > vectors/mesh_vectors.txt
./cppref/ref3 > vectors/trav_vectors.txt
./cppref/ref4 > vectors/pred_vectors.txt

"$RASC" ../_verifyB.as --path "$AS_STD" --lib "$AS_STD/assembly" --runtime stub -o verifyB.wasm

node verify.mjs
node verify2.mjs
node verify3.mjs
node golden.mjs
node exact.mjs
echo "verification: all green"
