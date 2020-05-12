#!/bin/bash
# Copyright 2016 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# 判断是否设置了全局变量VERBOSE_SCRIPT_LOGGING
# 如果设置了，那么打印传入该函数的命令
# 执行该命令
# 返回执行上诉命令的返回值
RunCommand() {
  VERBOSE_SCRIPT_LOGGING="1.0.0"
  if [[ -n "$VERBOSE_SCRIPT_LOGGING" ]]; then
    echo "♦ $*"
  fi
  "$@"
  return $?
}

#判断是否配置全局变量SCRIPT_OUTPUT_STREAM_FILE（文件输出路径），
#如果配置了，那么就将第二个参数$1 写入该文件中

# When provided with a pipe by the host Flutter build process, output to the
# pipe goes to stdout of the Flutter build process directly.
StreamOutput() {
  if [[ -n "$SCRIPT_OUTPUT_STREAM_FILE" ]]; then
    echo "$1" > $SCRIPT_OUTPUT_STREAM_FILE
  fi
}

# 将 标准输出 重定向到 标准错误输出
# 以标准输出格式输出 变量
EchoError() {
  echo "$@" 1>&2
}

# 如果 $1变量指定的文件或者文件连接<快捷方式> 都不存在，则返回-1，否则返回0
# -e filename 如果 filename存在，则为真
# -h filename 如果filename存在且是一个连接（快捷方式），则为真
AssertExists() {
  if [[ ! -e "$1" ]]; then
    if [[ -h "$1" ]]; then
      EchoError "The path $1 is a symlink to a path that does not exist"
    else
      EchoError "The path $1 does not exist"
    fi
    exit -1
  fi
  return 0
}


BuildApp() {
  local project_path="${SOURCE_ROOT}/.."
  echo "SOURCE_ROOT根目录："
  echo "$project_path"

  if [[ -n "$FLUTTER_APPLICATION_PATH" ]]; then
    project_path="${FLUTTER_APPLICATION_PATH}"
  fi
  echo "project_path项目目录："
  echo "$project_path"

  local target_path="lib/main.dart"
  if [[ -n "$FLUTTER_TARGET" ]]; then
    target_path="${FLUTTER_TARGET}"
  fi
  echo "target_path目录："
  echo "$target_path"

  local derived_dir="${SOURCE_ROOT}/Flutter"
  if [[ -e "${project_path}/.ios" ]]; then
    derived_dir="${project_path}/.ios/Flutter"
  fi
  echo "derived_dir目录："
  echo "$derived_dir"

  # Default value of assets_path is flutter_assets
  local assets_path="flutter_assets"
  # The value of assets_path can set by add FLTAssetsPath to AppFrameworkInfo.plist
  FLTAssetsPath=$(/usr/libexec/PlistBuddy -c "Print :FLTAssetsPath" "${derived_dir}/AppFrameworkInfo.plist" 2>/dev/null)
  if [[ -n "$FLTAssetsPath" ]]; then
    assets_path="${FLTAssetsPath}"
  fi
  echo "assets_path目录："
  echo "$assets_path"


  # 获取FLUTTER_BUILD_MODE，如果没有获取到，就使用Xcode build configuration的值
  # 赋值给build_mode变量
  # 并且根据构建模式，设置对应的artifact_variant变量的值
  # artifact_variant变量表示 Flutter.framework的所在目录，不同模式下，加载的Flutter.framework不一样

  # Use FLUTTER_BUILD_MODE if it's set, otherwise use the Xcode build configuration name
  # This means that if someone wants to use an Xcode build config other than Debug/Profile/Release,
  # they _must_ set FLUTTER_BUILD_MODE so we know what type of artifact to build.
  local build_mode="$(echo "${FLUTTER_BUILD_MODE:-${CONFIGURATION}}" | tr "[:upper:]" "[:lower:]")"
  echo "构建模式build_mode:"
  echo "$build_mode"

  local artifact_variant="unknown"
  case "$build_mode" in
    *release*) build_mode="release"; artifact_variant="ios-release";;
    *profile*) build_mode="profile"; artifact_variant="ios-profile";;
    *debug*) build_mode="debug"; artifact_variant="ios";;
    *)
      EchoError "========================================================================"
      EchoError "ERROR: Unknown FLUTTER_BUILD_MODE: ${build_mode}."
      EchoError "Valid values are 'Debug', 'Profile', or 'Release' (case insensitive)."
      EchoError "This is controlled by the FLUTTER_BUILD_MODE environment variable."
      EchoError "If that is not set, the CONFIGURATION environment variable is used."
      EchoError ""
      EchoError "You can fix this by either adding an appropriately named build"
      EchoError "configuration, or adding an appropriate value for FLUTTER_BUILD_MODE to the"
      EchoError ".xcconfig file for the current build configuration (${CONFIGURATION})."
      EchoError "========================================================================"
      exit -1;;
  esac

  # 如果是打包的话，那么必须使用 release模式
  # Archive builds (ACTION=install) should always run in release mode.
  if [[ "$ACTION" == "install" && "$build_mode" != "release" ]]; then
    EchoError "========================================================================"
    EchoError "ERROR: Flutter archive builds must be run in Release mode."
    EchoError ""
    EchoError "To correct, ensure FLUTTER_BUILD_MODE is set to release or run:"
    EchoError "flutter build ios --release"
    EchoError ""
    EchoError "then re-run Archive from Xcode."
    EchoError "========================================================================"
    exit -1
  fi

  local framework_path="${FLUTTER_ROOT}/bin/cache/artifacts/engine/${artifact_variant}"
  echo "本地flutter.framework的路径是："
  echo "$framework_path"

  AssertExists "${framework_path}"
  AssertExists "${project_path}"

  # flutter工程中，创建ios/Flutter子目录出来
  RunCommand mkdir -p -- "$derived_dir"
  AssertExists "$derived_dir"

  # 移除旧的App.framework  ios/Flutter/App.framework
  RunCommand rm -rf -- "${derived_dir}/App.framework"

  local flutter_engine_flag=""
  local local_engine_flag=""
  local flutter_framework="${framework_path}/Flutter.framework"
  local flutter_podspec="${framework_path}/Flutter.podspec"

  # 如果配置了 FLUTTER_ENGINE变量，就给flutter_engine_flag变量赋值
  if [[ -n "$FLUTTER_ENGINE" ]]; then
    flutter_engine_flag="--local-engine-src-path=${FLUTTER_ENGINE}"
  fi

  
  # 如果配置了 LOCAL_ENGINE 本地engine变量，就必须包含build_mode
  # 且如果配置了 LOCAL_ENGINE 本地engine变量
  # 就重新给flutter_framework 和 flutter_podspec 重新赋值
  if [[ -n "$LOCAL_ENGINE" ]]; then
    if [[ $(echo "$LOCAL_ENGINE" | tr "[:upper:]" "[:lower:]") != *"$build_mode"* ]]; then
      EchoError "========================================================================"
      EchoError "ERROR: Requested build with Flutter local engine at '${LOCAL_ENGINE}'"
      EchoError "This engine is not compatible with FLUTTER_BUILD_MODE: '${build_mode}'."
      EchoError "You can fix this by updating the LOCAL_ENGINE environment variable, or"
      EchoError "by running:"
      EchoError "  flutter build ios --local-engine=ios_${build_mode}"
      EchoError "or"
      EchoError "  flutter build ios --local-engine=ios_${build_mode}_unopt"
      EchoError "========================================================================"
      exit -1
    fi
    local_engine_flag="--local-engine=${LOCAL_ENGINE}"
    flutter_framework="${FLUTTER_ENGINE}/out/${LOCAL_ENGINE}/Flutter.framework"
    flutter_podspec="${FLUTTER_ENGINE}/out/${LOCAL_ENGINE}/Flutter.podspec"
  fi

  # 如果项目中, build setting里配置 Enable Bitcode 为YES，那么 bitcode_flag="--bitcode"
  local bitcode_flag=""
  if [[ $ENABLE_BITCODE == "YES" ]]; then
    bitcode_flag="--bitcode"
  fi

  
  # Flutter项目中， 
  # 如果/.ios路径存在
  # 删除项目目录/ios/Flutter/engine文件夹，再重新创建
  # copy Flutter.podspec和Flutter.framework进入engine文件夹中

  # 如果/.ios路径不存在
  # 删除/ios/Flutter/Flutter.framework
  # copy Flutter.podspec和Flutter.framework进入 项目目录/ios/Flutter 文件夹中
  if [[ -e "${project_path}/.ios" ]]; then
    RunCommand rm -rf -- "${derived_dir}/engine"
    mkdir "${derived_dir}/engine"
    RunCommand cp -r -- "${flutter_podspec}" "${derived_dir}/engine"
    RunCommand cp -r -- "${flutter_framework}" "${derived_dir}/engine"
  else
    RunCommand rm -rf -- "${derived_dir}/Flutter.framework"
    RunCommand cp -- "${flutter_podspec}" "${derived_dir}"
    RunCommand cp -r -- "${flutter_framework}" "${derived_dir}"
  fi

  # 保存project_path路径，压栈
  RunCommand pushd "${project_path}" > /dev/null

  AssertExists "${target_path}"
  

  local verbose_flag=""
  if [[ -n "$VERBOSE_SCRIPT_LOGGING" ]]; then
    verbose_flag="--verbose"
  fi

  # 编译的文件目录build_dir： 默认是 项目目录/build
  # 要是有设置FLUTTER_BUILD_DIR 那就用FLUTTER_BUILD_DIR，

  local build_dir="${FLUTTER_BUILD_DIR:-build}"

  local track_widget_creation_flag=""
  if [[ -n "$TRACK_WIDGET_CREATION" ]]; then
    track_widget_creation_flag="--track-widget-creation"
  fi

  # 如果build_mode不是 debug模式
  # 那么 不能编译 架构为i386 或者 x86_64 的目标则报错并退出返回-1
  if [[ "${build_mode}" != "debug" ]]; then
    StreamOutput " ├─Building Dart code..."
    # Transform ARCHS to comma-separated list of target architectures.
    local archs="${ARCHS// /,}"
    if [[ $archs =~ .*i386.* || $archs =~ .*x86_64.* ]]; then
      EchoError "========================================================================"
      EchoError "ERROR: Flutter does not support running in profile or release mode on"
      EchoError "the Simulator (this build was: '$build_mode')."
      EchoError "You can ensure Flutter runs in Debug mode with your host app in release"
      EchoError "mode by setting FLUTTER_BUILD_MODE=debug in the .xcconfig associated"
      EchoError "with the ${CONFIGURATION} build configuration."
      EchoError "========================================================================"
      exit -1
    fi
    
    # 执行 本地Flutter仓库里的 /bin/flutter可执行文件，执行命令失败就退出返回-1
    # 执行flutter命令是flutter build aot 并且带有以下参数
    RunCommand "${FLUTTER_ROOT}/bin/flutter" --suppress-analytics           \
      ${verbose_flag}                                                       \
      build aot                                                             \
      --output-dir="${build_dir}/aot"                                       \
      --target-platform=ios                                                 \
      --target="${target_path}"                                             \
      --${build_mode}                                                       \
      --ios-arch="${archs}"                                                 \
      ${flutter_engine_flag}                                                \
      ${local_engine_flag}                                                  \
      ${bitcode_flag}

    if [[ $? -ne 0 ]]; then
      EchoError "Failed to build ${project_path}."
      exit -1
    fi
    
    #flutter编译成功
    StreamOutput "done"
  
    #flutter编译生成的 App.framework的目录 是在 项目目录/build/aot/目录下
    local app_framework="${build_dir}/aot/App.framework"
    echo "release模式下 app_framework："
    echo "$app_framework"
 
    #把 项目目录/build/aot/App.framework 复制到 项目目录/ios/Flutter 目录下
    RunCommand cp -r -- "${app_framework}" "${derived_dir}"

    #如果是release模式下，
    #在 项目目录/build目录下创建 dSYMs.noindex文件夹
    #运行 xrun dysmutil工具，生成framework的dsym文件到 项目目录/build/dSYMs.noindex目录下
    #如果生成dsym文件失败，则打印错误并退出返回-1
    #生成dsym文件成功，则删除一些没用的debug的符号表？？？，删除失败则退出返回-1
    if [[ "${build_mode}" == "release" ]]; then
      StreamOutput " ├─Generating dSYM file..."
      # Xcode calls `symbols` during app store upload, which uses Spotlight to
      # find dSYM files for embedded frameworks. When it finds the dSYM file for
      # `App.framework` it throws an error, which aborts the app store upload.
      # To avoid this, we place the dSYM files in a folder ending with ".noindex",
      # which hides it from Spotlight, https://github.com/flutter/flutter/issues/22560.
      RunCommand mkdir -p -- "${build_dir}/dSYMs.noindex"
      RunCommand xcrun dsymutil -o "${build_dir}/dSYMs.noindex/App.framework.dSYM" "${app_framework}/App"
      if [[ $? -ne 0 ]]; then
        EchoError "Failed to generate debug symbols (dSYM) file for ${app_framework}/App."
        exit -1
      fi
      StreamOutput "done"

      StreamOutput " ├─Stripping debug symbols..."
      RunCommand xcrun strip -x -S "${derived_dir}/App.framework/App"
      if [[ $? -ne 0 ]]; then
        EchoError "Failed to strip ${derived_dir}/App.framework/App."
        exit -1
      fi
      StreamOutput "done"
    fi

  else
    
    # 在build_mode是 debug模式的情况下
    # 创建 项目目录/ios/Flutter/App.framework目录
    # 根据 ARCHS变量，设置 arch_flags
    RunCommand mkdir -p -- "${derived_dir}/App.framework"

    # Build stub for all requested architectures.
    local arch_flags=""
    read -r -a archs <<< "$ARCHS"
    for arch in "${archs[@]}"; do
      arch_flags="${arch_flags}-arch $arch "
    done
    
    # CH_TODO 这里的作用？？？
    # 程序的JIT编译快照？？？
    # xcrun clang的参数列表分析
    # 1、-x c  编译使用的c语言编译
    # 2、-dynamiclib 链接动态库？
    # 3、-Xlinker 传递后面的参数给链接器： -rpath = '@executable_path/Frameworks'   -rpath = '@loader_path/Frameworks'
    # @executable_path 这个变量表示可执行程序所在的目录
    # @loader_path 这个变量表示每一个被加载的 binary (包括App, dylib, framework,plugin等) 所在的目录
    # @rpath 只是一个保存着一个或多个路径的变量
    # 4、-o 输出文件的路径： 项目目录/App.framework/App

    RunCommand eval "$(echo "static const int Moo = 88;" | xcrun clang -x c \
        ${arch_flags} \
        -fembed-bitcode-marker \
        -dynamiclib \
        -Xlinker -rpath -Xlinker '@executable_path/Frameworks' \
        -Xlinker -rpath -Xlinker '@loader_path/Frameworks' \
        -install_name '@rpath/App.framework/App' \
        -o "${derived_dir}/App.framework/App" -)"
  fi

  #默认plistPath = 项目目录/ios/Flutter/AppFrameworkInfo.plist
  #如果项目目录中存在 /.ios文件，那么 plistPath = 项目目录/.ios/Flutter/AppFrameworkInfo.plist
  local plistPath="${project_path}/ios/Flutter/AppFrameworkInfo.plist"
  if [[ -e "${project_path}/.ios" ]]; then
    plistPath="${project_path}/.ios/Flutter/AppFrameworkInfo.plist"
  fi

  #把AppFrameworkInfo.plist的内容 复制到 /ios/Flutter/App.framework/Info.plist文件中
  RunCommand cp -- "$plistPath" "${derived_dir}/App.framework/Info.plist"

  
  #当目前不是debug 并且不是x86_64 结构体的时候，设置预编译参数 precompilation_flag
  local precompilation_flag=""
  if [[ "$CURRENT_ARCH" != "x86_64" ]] && [[ "$build_mode" != "debug" ]]; then
    precompilation_flag="--precompiled"
  fi

  
  # 执行 本地Flutter仓库里的 /bin/flutter可执行文件，执行命令失败就退出返回-1
  # 执行flutter的命令是： flutter build bundle ,并且带有以下参数
  # 编译成功，就输出文案，返回0
  StreamOutput " ├─Assembling Flutter resources..."
  RunCommand "${FLUTTER_ROOT}/bin/flutter"     \
    ${verbose_flag}                                                         \
    build bundle                                                            \
    --target-platform=ios                                                   \
    --target="${target_path}"                                               \
    --${build_mode}                                                         \
    --depfile="${build_dir}/snapshot_blob.bin.d"                            \
    --asset-dir="${derived_dir}/App.framework/${assets_path}"               \
    ${precompilation_flag}                                                  \
    ${flutter_engine_flag}                                                  \
    ${local_engine_flag}                                                    \
    ${track_widget_creation_flag}

  if [[ $? -ne 0 ]]; then
    EchoError "Failed to package ${project_path}."
    exit -1
  fi
  StreamOutput "done"
  StreamOutput " └─Compiling, linking and signing..."

  RunCommand popd > /dev/null

  echo "Project ${project_path} built and packaged successfully."
  return 0
}

# 读取app.framework/Info.plist文件中的 CFBundleExecutable字段
# Returns the CFBundleExecutable for the specified framework directory.
GetFrameworkExecutablePath() {
  local framework_dir="$1"

  local plist_path="${framework_dir}/Info.plist"
  local executable="$(defaults read "${plist_path}" CFBundleExecutable)"
  echo "${framework_dir}/${executable}"
}

# 给指定的可执行文件进行破坏性的瘦身
# 只保留指定的架构architectures
# Destructively thins the specified executable file to include only the
# specified architectures.
LipoExecutable() {
  local executable="$1"
  shift
  # Split $@ into an array.
  read -r -a archs <<< "$@"

  # Extract architecture-specific framework executables.
  local all_executables=()
  for arch in "${archs[@]}"; do
    local output="${executable}_${arch}"
    local lipo_info="$(lipo -info "${executable}")"
    if [[ "${lipo_info}" == "Non-fat file:"* ]]; then
      if [[ "${lipo_info}" != *"${arch}" ]]; then
        echo "Non-fat binary ${executable} is not ${arch}. Running lipo -info:"
        echo "${lipo_info}"
        exit 1
      fi
    else
      lipo -output "${output}" -extract "${arch}" "${executable}"
      if [[ $? == 0 ]]; then
        all_executables+=("${output}")
      else
        echo "Failed to extract ${arch} for ${executable}. Running lipo -info:"
        lipo -info "${executable}"
        exit 1
      fi
    fi
  done

  # Generate a merged binary from the architecture-specific executables.
  # Skip this step for non-fat executables.
  if [[ ${#all_executables[@]} > 0 ]]; then
    local merged="${executable}_merged"
    lipo -output "${merged}" -create "${all_executables[@]}"

    cp -f -- "${merged}" "${executable}" > /dev/null
    rm -f -- "${merged}" "${all_executables[@]}"
  fi
}

# 对$1参数中指定的framework 进行破坏性的瘦身
# 只保留指定的架构architectures
# Destructively thins the specified framework to include only the specified
# architectures.
ThinFramework() {
  local framework_dir="$1"
  shift

  local plist_path="${framework_dir}/Info.plist"
  local executable="$(GetFrameworkExecutablePath "${framework_dir}")"
  LipoExecutable "${executable}" "$@"
}

# 
ThinAppFrameworks() {
  local app_path="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
  local frameworks_dir="${app_path}/Frameworks"

  echo "对frameworks进行瘦身，frameworks的目录是: "
  echo "$frameworks_dir"
  echo "进行瘦身的分别是："
  # 对
  [[ -d "$frameworks_dir" ]] || return 0
  find "${app_path}" -type d -name "*.framework" | while read framework_dir; do
    echo "$framework_dir"
    ThinFramework "$framework_dir" "$ARCHS"
  done
  echo "瘦身结束"
}

# 让 App.framework内嵌到 app中，并且 flutter_assets作为资源
# Adds the App.framework as an embedded binary and the flutter_assets as
# resources.
EmbedFlutterFrameworks() {
  AssertExists "${FLUTTER_APPLICATION_PATH}"

  # Prefer the hidden .ios folder, but fallback to a visible ios folder if .ios
  # doesn't exist.
  #默认flutter_ios_out_folder = 项目目录/.ios/Flutter
  #默认flutter_ios_engine_folder = 项目目录/.ios/Flutter/engine
  #如果.ios目录不存在的话，
  #flutter_ios_out_folder = 项目目录/ios/Flutter
  #flutter_ios_engine_folder = 项目目录/ios/Flutter
  local flutter_ios_out_folder="${FLUTTER_APPLICATION_PATH}/.ios/Flutter"
  local flutter_ios_engine_folder="${FLUTTER_APPLICATION_PATH}/.ios/Flutter/engine"
  if [[ ! -d ${flutter_ios_out_folder} ]]; then
    flutter_ios_out_folder="${FLUTTER_APPLICATION_PATH}/ios/Flutter"
    flutter_ios_engine_folder="${FLUTTER_APPLICATION_PATH}/ios/Flutter"
  fi

  AssertExists "${flutter_ios_out_folder}"


  # Embed App.framework from Flutter into the app (after creating the Frameworks directory
  # if it doesn't already exist).
  #默认 xcode_frameworks_dir = 项目产品目录/PRODUCT_NAME.app/Frameworks  也就是生成的.app的 frameworks目录
  #如果没有这个目录，就创建这个目录
  #把flutter编译后得到的App.framework (在flutter_ios_out_folder目录中）放入到 xcode_frameworks_dir目录下
  local xcode_frameworks_dir=${BUILT_PRODUCTS_DIR}"/"${PRODUCT_NAME}".app/Frameworks"
  RunCommand mkdir -p -- "${xcode_frameworks_dir}"
  RunCommand cp -Rv -- "${flutter_ios_out_folder}/App.framework" "${xcode_frameworks_dir}"

  # Embed the actual Flutter.framework that the Flutter app expects to run against,
  # which could be a local build or an arch/type specific build.
  # Remove it first since Xcode might be trying to hold some of these files - this way we're
  # sure to get a clean copy.
  #移除xcode_frameworks_dir目录里存在的 Flutter.framework
  #把flutter_ios_engine_folder目录下的 Flutter.framework 复制到xcode_frameworks_dir，也就是 app的frameworks目录下
  RunCommand rm -rf -- "${xcode_frameworks_dir}/Flutter.framework"
  RunCommand cp -Rv -- "${flutter_ios_engine_folder}/Flutter.framework" "${xcode_frameworks_dir}/"

  # Sign the binaries we moved.
  # 签名
  # 给 App.framework/App 和 Flutter.framework/Flutter 都签名
  local identity="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-$CODE_SIGN_IDENTITY}"
  if [[ -n "$identity" && "$identity" != "\"\"" ]]; then
    RunCommand codesign --force --verbose --sign "${identity}" -- "${xcode_frameworks_dir}/App.framework/App"
    RunCommand codesign --force --verbose --sign "${identity}" -- "${xcode_frameworks_dir}/Flutter.framework/Flutter"
  fi
}

# Main entry point.

# TODO(cbracken): improve error handling, then enable set -e

if [[ $# == 0 ]]; then
  # Backwards-compatibility: if no args are provided, build.
  BuildApp
else
  case $1 in
    "build")
      BuildApp ;;
    "thin")
      ThinAppFrameworks ;;
    "embed")
      EmbedFlutterFrameworks ;;
  esac
fi
