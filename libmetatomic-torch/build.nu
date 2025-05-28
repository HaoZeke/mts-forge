#!/usr/bin/env nu

let host_prefix_expanded = ($env.PREFIX | path expand)
# Remember to build with rattler-build build --no-build-id --recipe ..
if ($env.USE_SCCACHE == "1") {
let current_cxx = ($env.CXX? | default (which cpp).path.0)
let current_cc = ($env.CC? | default (which cc).path.0)
 if not ($current_cc starts-with "sccache") {
 $env.CXX = $"sccache ($current_cxx)"
 $env.CC = $"sccache ($current_cc)"
 }
}

let existing_cxxflags = ($env.CXXFLAGS? | default '')
$env.CXXFLAGS = $"-D_LIBCPP_DISABLE_AVAILABILITY ($existing_cxxflags)" | str trim

^cmake -G Ninja ($env.CMAKE_ARGS) -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=($host_prefix_expanded) .
^cmake --build . --config Release --target install
