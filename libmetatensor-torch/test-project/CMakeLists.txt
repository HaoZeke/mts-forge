cmake_minimum_required(VERSION 3.16)

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

project(test-metatensor-torch CXX)

find_package(metatensor_torch)

add_executable(main main.cpp)
target_link_libraries(main metatensor_torch)

enable_testing()
add_test(NAME main COMMAND main)
