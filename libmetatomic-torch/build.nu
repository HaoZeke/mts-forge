#!/usr/bin/env nu

if $env.USE_SCCACHE == 1 {
 $env.CXX = ($env.CXX | prepend 'sccache ')
 $env.CC = ($env.CC | prepend 'sccache ')
}

# --- CPPFLAGS for Plumed Kernel ---
$env.CXXFLAGS = (($env.CXXFLAGS? | default []) | append "-D_LIBCPP_DISABLE_AVAILABILITY")

^cmake -G Ninja ($env.CMAKE_ARGS) -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=($env.PREFIX) .
^cmake --build . --config Release --target install
