# Usage:
# cd $GITROOT/ci/gha
# nickel export --format yaml workflow.ncl -o ../../.github/workflows/build.yml
let makeBuildStep = fun packageName =>
  {
    name = "Build %{packageName}",
    shell = "bash",
    env = {
      TARGET_PLATFORM = m%"${{ matrix.target }}"%,
      MACOSX_DEPLOYMENT_TARGET = "11.0",
    },
    run = m%"pixi r build-ci %{packageName} $TARGET_PLATFORM"%,
  }
in
let workflow = {
  name = "Build all packages",
  on = {
    push = {
      branches = ["main"],
    },
    workflow_dispatch = null,
    pull_request = {
      branches = ["main"],
    }
  },
  concurrency = {
    group = "${{ github.workflow }}-${{ github.ref }}",
    cancel-in-progress = true,
  },
  jobs = {
    build = {
      strategy = {
        matrix = {
          include = [
            { target = "linux-64", os = "ubuntu-22.04" },
            # { target= "win-64",    os= "windows-latest" },
            # force older macos-13 to get x86_64 runners
            { target = "osx-64", os = "macos-13" },
            { target = "osx-arm64", os = "macos-14" },
            { target = "linux-aarch64", os = "ubuntu-22.04-arm" },
          ],
        },
        fail-fast = false,
      },
      permissions = {
        id-token = "write",
        contents = "read",
      },
      runs-on = "${{ matrix.os }}",
      steps = [
        { uses = "actions/checkout@v4", with = { fetch-depth = 1 } },
        { uses = "prefix-dev/setup-pixi@v0.8.8", with = { pixi-version = "v0.46.0", cache = true } },
        { name = "Add .pixi/envs/default to the $PATH", shell = "bash", run = m%"echo "$(pwd)/.pixi/envs/default/bin" >> $GITHUB_PATH"% },
        {
          name = "Cache rattler-build built packages for ${{ matrix.target }}",
          uses = "actions/cache@v4",
          with = {
            # Path to platform-specific built packages
            path = "${{ github.workspace }}/output/${{ matrix.target }}",
            key = "${{ runner.os }}-${{ matrix.target }}-rattler-pkgs-${{ github.ref }}-${{ hashFiles('**/recipe.yaml') }}",
            restore-keys = m%"
${{ runner.os }}-${{ matrix.target }}-rattler-pkgs-${{ github.ref }}-
${{ runner.os }}-${{ matrix.target }}-rattler-pkgs-refs/heads/main-
"%,
          }
        },
        makeBuildStep "plumed-metatomic",
        makeBuildStep "py-plumed-metatomic",
        {
          name = "Upload all packages",
          shell = "bash",
          "if" = "github.event_name == 'push'",
          env = {
            BINSTAR_TOKEN = m%"${{ secrets.BINSTAR_TOKEN }}"%,
            STAGING_BINSTAR_TOKEN = m%"${{ secrets.BINSTAR_TOKEN }}"%,
          },
          run = m%"
shopt -s nullglob
EXIT_CODE=0
for pkg in $(find output -type f \( -name "*.conda" -o -name "*.tar.bz2" \) ); do
  if ! rattler-build upload anaconda -o metatensor -c main -a $BINSTAR_TOKEN "${pkg}"; then
    EXIT_CODE=0 # This is a cop out, fix the exit code later
    # The issue is that there can be duplicates, which are annoying
  fi
done
exit $EXIT_CODE
"%,
        },
      ],
    },
  },
}
in workflow
