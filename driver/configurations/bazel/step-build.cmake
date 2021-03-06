# -*- mode: cmake -*-
# vi: set ft=cmake :

# Copyright (c) 2016, Massachusetts Institute of Technology.
# Copyright (c) 2016, Toyota Research Institute.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# CTEST_SOURCE_DIRECTORY and CTEST_BINARY_DIRECTORY are set in bazel.cmake.

notice("CTest Status: RUNNING BAZEL")

begin_stage(
  PROJECT_NAME "Drake"
  BUILD_NAME "${DASHBOARD_BUILD_NAME}")

ctest_update(SOURCE "${CTEST_SOURCE_DIRECTORY}"
  RETURN_VALUE DASHBOARD_UPDATE_RETURN_VALUE QUIET)

set(DASHBOARD_BUILD_EVENT_JSON_FILE "${CTEST_BINARY_DIRECTORY}/BUILD.JSON")
set(DASHBOARD_BUILD_EVENT_OPTION "--build_event_json_file=${DASHBOARD_BUILD_EVENT_JSON_FILE}")

set(CTEST_BUILD_COMMAND
  "${DASHBOARD_BAZEL_COMMAND} ${DASHBOARD_BAZEL_STARTUP_OPTIONS} test ${DASHBOARD_BAZEL_BUILD_OPTIONS} ${DASHBOARD_BAZEL_TEST_OPTIONS} ${DASHBOARD_BUILD_EVENT_OPTION} ...")

if(PACKAGE)
  message(STATUS "Creating package output directory...")
  execute_process(COMMAND sudo "${CMAKE_COMMAND}" -E make_directory /opt/drake
    RESULT_VARIABLE MAKE_DIRECTORY_RESULT_VARIABLE
    OUTPUT_VARIABLE MAKE_DIRECTORY_OUTPUT_VARIABLE
    ERROR_VARIABLE MAKE_DIRECTORY_OUTPUT_VARIABLE
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT MAKE_DIRECTORY_RESULT_VARIABLE EQUAL 0)
    fatal("creation of package output directory was not successful"
      MAKE_DIRECTORY_OUTPUT_VARIABLE)
  endif()
  execute_process(COMMAND sudo chmod 0777 /opt/drake
    RESULT_VARIABLE CHMOD_RESULT_VARIABLE
    OUTPUT_VARIABLE CHMOD_OUTPUT_VARIABLE
    ERROR_VARIABLE CHMOD_OUTPUT_VARIABLE)
  if(NOT CHMOD_RESULT_VARIABLE EQUAL 0)
    fatal("setting permissions on package output directory was not successful"
      CHMOD_OUTPUT_VARIABLE)
  endif()
  set(CTEST_BUILD_COMMAND "${DASHBOARD_BAZEL_COMMAND} ${DASHBOARD_BAZEL_STARTUP_OPTIONS} run ${DASHBOARD_BAZEL_BUILD_OPTIONS} ${DASHBOARD_BUILD_EVENT_OPTION} //:install -- /opt/drake")
endif()

set(CTEST_CUSTOM_ERROR_EXCEPTION "^WARNING: " ":[0-9]+: Failure$")
set(CTEST_CUSTOM_ERROR_MATCH "^ERROR: " "^FAIL: " "^TIMEOUT: ")
set(CTEST_CUSTOM_WARNING_MATCH "^WARNING: ")

if(EXISTS "${CTEST_SOURCE_DIRECTORY}/CTestCustom.cmake.in")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E copy
    "${CTEST_SOURCE_DIRECTORY}/CTestCustom.cmake.in"
    "${CTEST_BINARY_DIRECTORY}/CTestCustom.cmake")
  ctest_read_custom_files("${CTEST_BINARY_DIRECTORY}")
endif()

ctest_build(BUILD "${DASHBOARD_SOURCE_DIRECTORY}"
  NUMBER_ERRORS DASHBOARD_NUMBER_BUILD_ERRORS
  NUMBER_WARNINGS DASHBOARD_NUMBER_BUILD_WARNINGS
  RETURN_VALUE DASHBOARD_BUILD_RETURN_VALUE QUIET)

# Number of warnings is not accurate since processing occurs on the CDash
# server.
set(DASHBOARD_NUMBER_BUILD_WARNINGS 0)

# https://bazel.build/blog/2016/01/27/continuous-integration.html
if(DASHBOARD_BUILD_RETURN_VALUE EQUAL 1)
  # Build failed.
  set(DASHBOARD_FAILURE ON)
  list(APPEND DASHBOARD_FAILURES "BAZEL BUILD")
elseif(DASHBOARD_BUILD_RETURN_VALUE EQUAL 2)
  # Command line problem, bad or illegal flags or command combination, or bad
  # environment variables. Your command line must be modified.
  set(DASHBOARD_FAILURE ON)
  list(APPEND DASHBOARD_FAILURES "BAZEL COMMAND OR ENVIRONMENT")
elseif(DASHBOARD_BUILD_RETURN_VALUE EQUAL 3)
  # Build OK, but some tests failed or timed out.
  set(DASHBOARD_UNSTABLE ON)
  list(APPEND DASHBOARD_UNSTABLES "BAZEL TEST")
elseif(DASHBOARD_BUILD_RETURN_VALUE EQUAL 4)
  # Build successful, but no tests were found even though testing was requested.
  set(DASHBOARD_UNSTABLE ON)
  list(APPEND DASHBOARD_UNSTABLES "BAZEL TEST")
elseif(DASHBOARD_BUILD_RETURN_VALUE EQUAL 8)
  # Build interrupted, but we terminated with an orderly shutdown.
  set(DASHBOARD_FAILURE ON)
  list(APPEND DASHBOARD_FAILURES "BAZEL")
elseif(NOT DASHBOARD_BUILD_RETURN_VALUE EQUAL 0)
  set(DASHBOARD_FAILURE ON)
  list(APPEND DASHBOARD_FAILURES "BAZEL")
endif()

ctest_submit(PARTS Update RETRY_COUNT 4 RETRY_DELAY 15 QUIET)
ctest_submit(PARTS Upload RETRY_COUNT 4 RETRY_DELAY 15 QUIET)
ctest_submit(CDASH_UPLOAD "${DASHBOARD_BUILD_EVENT_JSON_FILE}"
  CDASH_UPLOAD_TYPE BazelJSON
  RETRY_COUNT 4 RETRY_DELAY 15
  QUIET)

if(COVERAGE)
  set(KCOV_MERGED "${DASHBOARD_SOURCE_DIRECTORY}/bazel-kcov/kcov-merged")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E copy "${KCOV_MERGED}/cobertura.xml" "${KCOV_MERGED}/coverage.xml")
  set(ENV{COBERTURADIR} "${KCOV_MERGED}")
  ctest_coverage(RETURN_VALUE DASHBOARD_COVERAGE_RETURN_VALUE QUIET)
  ctest_submit(PARTS Coverage RETRY_COUNT 4 RETRY_DELAY 15 QUIET)
endif()

if(PACKAGE AND NOT DASHBOARD_FAILURE AND NOT DASHBOARD_UNSTABLE)
  message(STATUS "Creating package archive...")
  string(TIMESTAMP DATE "%Y%m%d")
  string(TIMESTAMP TIME "%H%M%S")
  execute_process(COMMAND "${CTEST_GIT_COMMAND}" rev-parse HEAD
    WORKING_DIRECTORY "${CTEST_SOURCE_DIRECTORY}"
    RESULT_VARIABLE GIT_REV_PARSE_RESULT_VARIABLE
    OUTPUT_VARIABLE GIT_REV_PARSE_OUTPUT_VARIABLE
    ERROR_VARIABLE GIT_REV_PARSE_ERROR_VARIABLE
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT GIT_REV_PARSE_RESULT_VARIABLE EQUAL 0)
    message("${GIT_REV_PARSE_OUTPUT_VARIABLE}")
    message("${GIT_REV_PARSE_ERROR_VARIABLE}")
    set(DASHBOARD_UNSTABLE ON)
    list(APPEND DASHBOARD_UNSTABLES "BAZEL PACKAGE ARCHIVE CREATION")
  endif()
  file(WRITE /opt/drake/share/doc/drake/VERSION.TXT "${DATE}${TIME} ${GIT_REV_PARSE_OUTPUT_VARIABLE}")
  if(APPLE)
    set(DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION mac)
  elseif(DASHBOARD_UNIX_DISTRIBUTION_VERSION VERSION_LESS 16.04)
    set(DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION trusty)
  else()
    set(DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION xenial)
  endif()
  if(DASHBOARD_TRACK STREQUAL "Nightly")
    set(DASHBOARD_PACKAGE_ARCHIVE_NAME "drake-${DATE}-${DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION}.tar.gz")
  else()
    set(DASHBOARD_PACKAGE_ARCHIVE_NAME "drake-${DATE}${TIME}-${GIT_REV_PARSE_OUTPUT_VARIABLE}-${DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION}.tar.gz")
  endif()
  if(NOT DASHBOARD_UNSTABLE)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar czf "${DASHBOARD_WORKSPACE}/${DASHBOARD_PACKAGE_ARCHIVE_NAME}" drake
      WORKING_DIRECTORY /opt
      RESULT_VARIABLE TAR_RESULT_VARIABLE
      OUTPUT_VARIABLE TAR_OUTPUT_VARIABLE
      ERROR_VARIABLE TAR_OUTPUT_VARIABLE
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT TAR_RESULT_VARIABLE EQUAL 0)
      message("${TAR_OUTPUT_VARIABLE}")
      set(DASHBOARD_UNSTABLE ON)
      list(APPEND DASHBOARD_UNSTABLES "BAZEL PACKAGE ARCHIVE CREATION")
    endif()
  endif()
  if(PACKAGE STREQUAL "publish")
    if(DASHBOARD_TRACK STREQUAL "Nightly")
      set(DASHBOARD_PACKAGE_ARCHIVE_CACHE_CONTROL_MAX_AGE 31536000)  # 365 days.
      set(DASHBOARD_PACKAGE_ARCHIVE_LATEST_CACHE_CONTROL_MAX_AGE 64800)  # 18 hours.
      set(DASHBOARD_PACKAGE_ARCHIVE_STORAGE_CLASS STANDARD)
    else()
      set(DASHBOARD_PACKAGE_ARCHIVE_CACHE_CONTROL_MAX_AGE 2419200)  # 28 days.
      set(DASHBOARD_PACKAGE_ARCHIVE_LATEST_CACHE_CONTROL_MAX_AGE 2700)  # 45 minutes.
      set(DASHBOARD_PACKAGE_ARCHIVE_STORAGE_CLASS REDUCED_REDUNDANCY)
    endif()
    if(DASHBOARD_TRACK STREQUAL "Experimental")
      set(DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS 1)
    else()
      set(DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS 2)
    endif()
    string(TOLOWER "${DASHBOARD_TRACK}" DASHBOARD_PACKAGE_ARCHIVE_FOLDER)
    if(NOT DASHBOARD_UNSTABLE)
      message(STATUS "Uploading nightly package archive 1 of ${DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS} to AWS S3...")
      execute_process(
        COMMAND ${DASHBOARD_AWS_COMMAND} s3 cp
          --acl public-read
          --cache-control max-age=${DASHBOARD_PACKAGE_ARCHIVE_CACHE_CONTROL_MAX_AGE}
          --storage-class ${DASHBOARD_PACKAGE_ARCHIVE_STORAGE_CLASS}
          "${DASHBOARD_WORKSPACE}/${DASHBOARD_PACKAGE_ARCHIVE_NAME}"
          "s3://drake-packages/drake/${DASHBOARD_PACKAGE_ARCHIVE_FOLDER}/${DASHBOARD_PACKAGE_ARCHIVE_NAME}"
        RESULT_VARIABLE DASHBOARD_AWS_S3_RESULT_VARIABLE
        OUTPUT_VARIABLE DASHBOARD_AWS_S3_OUTPUT_VARIABLE
        ERROR_VARIABLE DASHBOARD_AWS_S3_OUTPUT_VARIABLE)
      message("${DASHBOARD_AWS_S3_OUTPUT_VARIABLE}")
      if(DASHBOARD_AWS_S3_RESULT_VARIABLE EQUAL 0)
        message(STATUS "Package URL 1 of ${DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS}: https://drake-packages.csail.mit.edu/drake/${DASHBOARD_PACKAGE_ARCHIVE_FOLDER}/${DASHBOARD_PACKAGE_ARCHIVE_NAME}")
      else()
        set(DASHBOARD_UNSTABLE ON)
        list(APPEND DASHBOARD_UNSTABLES "BAZEL NIGHTLY PACKAGE ARCHIVE UPLOAD 1 OF ${DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS}")
      endif()
    endif()
    if(NOT DASHBOARD_UNSTABLE AND DASHBOARD_PACKAGE_ARCHIVE_TOTAL_UPLOADS EQUAL 2)
      message(STATUS "Uploading nightly package archive 2 of 2 to AWS S3...")
      execute_process(
        COMMAND ${DASHBOARD_AWS_COMMAND} s3 cp
          --acl public-read
          --cache-control max-age=${DASHBOARD_PACKAGE_ARCHIVE_LATEST_CACHE_CONTROL_MAX_AGE}
          --storage-class ${DASHBOARD_PACKAGE_ARCHIVE_STORAGE_CLASS}
          "${DASHBOARD_WORKSPACE}/${DASHBOARD_PACKAGE_ARCHIVE_NAME}"
          "s3://drake-packages/drake/${DASHBOARD_PACKAGE_ARCHIVE_FOLDER}/drake-latest-${DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION}.tar.gz"
        RESULT_VARIABLE DASHBOARD_AWS_S3_RESULT_VARIABLE
        OUTPUT_VARIABLE DASHBOARD_AWS_S3_OUTPUT_VARIABLE
        ERROR_VARIABLE DASHBOARD_AWS_S3_OUTPUT_VARIABLE)
      message("${DASHBOARD_AWS_S3_OUTPUT_VARIABLE}")
      if(DASHBOARD_AWS_S3_RESULT_VARIABLE EQUAL 0)
        message(STATUS "Package URL 2 of 2: https://drake-packages.csail.mit.edu/drake/${DASHBOARD_PACKAGE_ARCHIVE_FOLDER}/drake-latest-${DASHBOARD_PACKAGE_ARCHIVE_DISTRIBUTION}.tar.gz")
      else()
        set(DASHBOARD_UNSTABLE ON)
        list(APPEND DASHBOARD_UNSTABLES "BAZEL NIGHTLY PACKAGE ARCHIVE UPLOAD 2 OF 2")
      endif()
    endif()
  endif()
endif()
