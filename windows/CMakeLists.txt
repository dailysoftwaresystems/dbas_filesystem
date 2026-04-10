cmake_minimum_required(VERSION 3.14)

# Read properties from pubspec.yaml
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml" PUBSPEC_CONTENT)
string(REGEX MATCH "name: ([^\n]+)" _ "${PUBSPEC_CONTENT}")
set(PUBSPEC_NAME "${CMAKE_MATCH_1}")
string(REGEX MATCH "version: ([^\n]+)" _ "${PUBSPEC_CONTENT}")
set(PUBSPEC_VERSION "${CMAKE_MATCH_1}")
string(REGEX MATCH "description: \"?([^\"\n]+)\"?" _ "${PUBSPEC_CONTENT}")
set(PUBSPEC_DESCRIPTION "${CMAKE_MATCH_1}")

set(PROJECT_NAME "${PUBSPEC_NAME}")
project(${PROJECT_NAME} VERSION ${PUBSPEC_VERSION} DESCRIPTION "${PUBSPEC_DESCRIPTION}" LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.27)

set(PLUGIN_NAME "dbas_filesystem_plugin")

list(APPEND PLUGIN_SOURCES
  "dbas_filesystem_plugin.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/dbas_filesystem/dbas_filesystem_plugin_c_api.h"
  "dbas_filesystem_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(dbas_filesystem_bundled_libraries
  ""
  PARENT_SCOPE
)
