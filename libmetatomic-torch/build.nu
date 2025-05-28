#!/usr/bin/env nu

if $env.USE_SCCACHE == 1 {
 $env.CXX = ($env.CXX | prepend 'sccache ')
 $env.CC = ($env.CC | prepend 'sccache ')
}

let existing_cppflags = ($env.CPPFLAGS? | default '')
$env.CPPFLAGS = $"-D_LIBCPP_DISABLE_AVAILABILITY ($existing_cppflags)" | str trim
let existing_cppflags = ($env.CXXFLAGS? | default '')
$env.CXXFLAGS = $"-D_LIBCPP_DISABLE_AVAILABILITY ($existing_cppflags)" | str trim

^cmake -G Ninja ($env.CMAKE_ARGS) -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=($env.PREFIX) .
^cmake --build . --config Release --target install
