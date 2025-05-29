#!/usr/bin/env nu

let host_prefix_expanded = ($env.PREFIX | path expand)
let psuffix = ($env.PROG_PREFIX)
let use_mpi = $env.USE_MPI

if ($env.USE_MPI == "1") {
 $env.CXX = $"($host_prefix_expanded)/bin/mpicxx"
 $env.CC = $"($host_prefix_expanded)/bin/mpicc"
}

# Remember to build with rattler-build build --no-build-id --recipe ..
if ($env.USE_SCCACHE == "1") {
let current_cxx = ($env.CXX? | default (which cpp).path.0)
let current_cc = ($env.CC? | default (which cc).path.0)
 if not ($current_cc starts-with "sccache") {
 $env.CXX = $"sccache ($current_cxx)"
 $env.CC = $"sccache ($current_cc)"
 }
}

# --- Linux Specifics ---
if ($nu.os-info.name == "linux") {
    # STATIC_LIBS is a PLUMED specific option and is required on Linux for the following reason:
    # When using env modules the dependent libraries can be found through the
    # LD_LIBRARY_PATH or encoded configuring with -rpath.
    # Conda does not use LD_LIBRARY_PATH and it is thus necessary to suggest where libraries are.
    $env.STATIC_LIBS = $"-Wl,-rpath-link,($host_prefix_expanded)/lib"

    # --- LDFLAGS Setup ---
    let host_lib_path = $"($host_prefix_expanded)/lib"
    let required_host_ldflags_additions = [
        $"-L($host_lib_path)",
        $"-Wl,-rpath,($host_lib_path)",
        $"-Wl,-rpath-link,($host_lib_path)"
    ]

    let current_ldflags_list = ($env.LDFLAGS? | default "" | split row " " | where not ($it == ""))

    # Prepend our required host LDFLAGS additions, then add the existing LDFLAGS.
    # 'uniq' will handle if rattler-build eventually provides some of these for Nu too.
    $env.LDFLAGS = (
        $required_host_ldflags_additions
        | append $current_ldflags_list # Add existing flags after our crucial ones
        | uniq # Remove duplicates if any overlap
        | str join " " | str trim
    )
    print $"INFO: Nushell script set LDFLAGS to: ($env.LDFLAGS)"
    # --- End LDFLAGS ---
}

$env.CFLAGS = [
  ($env.CFLAGS? | default ''),
] | str replace --all --regex '-O[*[:xdigit:]+]' "-O3"
  | uniq | str join ' ' | str trim

$env.CPPFLAGS = [
  # we also store path so that software linking libplumedWrapper.a knows where libplumedKernel can be found.
  $"-D__PLUMED_DEFAULT_KERNEL=($host_prefix_expanded)/lib/libplumedKernel($env.SHLIB_EXT?)",
  $"-I($host_prefix_expanded)/include/",
  # libtorch puts some headers in a non-standard place
  $"-I($host_prefix_expanded)/include/torch/csrc/api/include",
  ($env.CPPFLAGS? | default ''),
] | str replace --all --regex '-O[*[:xdigit:]+]' "-O3"
  | uniq | str join ' ' | str trim

$env.CXXFLAGS = [
 "-D_LIBCPP_DISABLE_AVAILABILITY",
 # Reasonable default
 ($env.CXXFLAGS? | default $env.CPPFLAGS)
] | str replace --all --regex '-O[*[:xdigit:]+]' "-O3"
  | uniq | str join ' ' | str trim

let additional_libs = [
 # Deps for metatomic PLUMED
 "dl"
 "metatomic_torch",
 "metatensor",
 "torch",
 "c10",
 "torch_cpu",
 # Here because of --disable-libsearch later
 "boost_serialization",
 "fftw3",
 "gsl",
 "gslcblas",
 "lapack",
 "blas",
 (if $nu.os-info.name == "linux" {"rt"} else "_INVALID"),
 "z"
] | each {|e| if $e != "_INVALID" {$"-l($e)"}}
  | uniq | str join ' '

let existing_libs = ($env.LIBS? | default '')
$env.LIBS = $"($additional_libs) ($existing_libs) "

# --- Configure ---
let configure_args = [
    $"--prefix=($host_prefix_expanded)",
    "--disable-python",
    $"--program-suffix=($psuffix)",
    (if $use_mpi == "1" {"--enable-mpi"} else "--disable-mpi"),
    "--disable-libsearch",
    "--disable-static-patch",
    "--disable-static-archive",
    "--disable-molfile-plugins",
    "--enable-modules=all",
    "--enable-boost_serialization",
    "--enable-libmetatomic",
    "--enable-libtorch"
]

print $"INFO: Running configure with args: ($configure_args | str join ' ')"
# External commands will get LIBS, CPPFLAGS, CXXFLAGS as space-separated strings
# due to the to_string closure in ENV_CONVERSIONS.
^./configure ...$configure_args

# --- Make ---
let cpu_count = $env.CPU_COUNT? | default (sys cpu | length)

print $"INFO: Running make -j($cpu_count)"
^make $"-j($cpu_count)"

print "INFO: Running make install"
^make install

print "INFO: Nushell build script finished."

# References
# [1]: https://github.com/nushell/nushell/discussions/14471
# [2]: https://github.com/sarvex/.config/blob/d0e290ffda2fe323a3142a2cefab93ed97097da2/config.nu#L42-L60
