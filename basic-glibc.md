```bash
docker run -it --rm -v "$PWD:/workspace" -w /workspace llvm-builder bash
```
```bash
export TAG="19.1.2_$(date +%Y%m%d)"
```
try to compile
```bash
./release.sh aarch64-linux-gnu
```
got
```bash
CMake Error at /opt/cmake-3.25.3-linux-aarch64/share/cmake-3.25/Modules/FindPackageHandleStandardArgs.cmake:230 (message):
  Could NOT find Python3 (missing: Python3_EXECUTABLE Interpreter) (Required
  is at least version "3.0")
Call Stack (most recent call first):
  /opt/cmake-3.25.3-linux-aarch64/share/cmake-3.25/Modules/FindPackageHandleStandardArgs.cmake:600 (_FPHSA_FAILURE_MESSAGE)
  /opt/cmake-3.25.3-linux-aarch64/share/cmake-3.25/Modules/FindPython/Support.cmake:3247 (find_package_handle_standard_args)
  /opt/cmake-3.25.3-linux-aarch64/share/cmake-3.25/Modules/FindPython3.cmake:490 (include)
  CMakeLists.txt:943 (find_package)
```