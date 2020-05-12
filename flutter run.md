两个目录：

flutter仓库目录：从flutter的git仓库 clone下来的本地目录

项目目录：创建的应用的目录

创建应用命令如下：

```
flutter create ****(项目名)

这个flutter: 是在系统的环境变量中设置的目录下的flutter可执行文件
export PATH=/Users/chunhongwang/install/flutter/bin:$PATH
```

#### flutter命令

用文本的方式，打开flutter可执行文件，看此文件的内容，知道它的核心命令是：

```
"$DART" $FLUTTER_TOOL_ARGS "$SNAPSHOT_PATH" "$@"
```

其中：
DART = flutter仓库目录/bin/cache/dart-sdk
SNAPSHOT_PATH = flutter仓库目录/bin/cache/flutter_tools.snapshot

意思是：用dart解释器（？？？）执行flutter_tools.snapshot文件，也就是执行flutter_tools.dart的main()方法，所以以上命令相当于

```
/bin/cache/dart-sdk/bin/dart $FLUTTER_TOOL_ARGS "$FLUTTER_ROOT/packages/flutter_tools/bin/flutter_tools.dart" "$@"
```

继续查看```flutter_tools.dart```文件，内容如下，也就是执行到```executable.dart```文件

```
import 'package:flutter_tools/executable.dart' as executable;

void main(List<String> args) {
  executable.main(args);
}
```

查看```executable.dart```文件，可以发现所有的命令都加入到_commands，而不同的命令有对应的实现类，举例有：

```
flutter create -> CreateCommand
flutter run -> RunCommand
flutter build aot -> BuildAotCommand
flutter build bundle -> BuildBundleCommand
```

综上过程可以知道，执行的flutter命令的实现都在 flutter仓库/bin/packages/flutter_tools目录里。

###flutter create ***(项目名)命令

也就是```CreateCommand```，主要工作是就是：创建项目目录，以及安卓和ios的工程，以及默认的```lib/main.dart```等

###flutter run ios

也就是```run.dart中的RunCommand类```

```dart
//找到所有的目标设备
devices = await findAllTargetDevices();

//以下三种分别是是什么？？？
如果是 HhotMode && !webMode:
   执行HotRunner().run()
如果是WebMode:
   执行 webRunnerFactory.createWebRunner().run()
否则：
   执行 ColdRunner().run()
...
...
...
最终，执行到
device.startApp(
      package,
      mainPath: hotRunner.mainPath,
      debuggingOptions: hotRunner.debuggingOptions,
      platformArgs: platformArgs,
      route: route,
      prebuiltApplication: prebuiltMode,
      ipv6: hotRunner.ipv6,
    );
针对不同的设备种类，有不同的device的实现，比如
android_device.dart
fuchsia_device.dart
simulator.dart
macos_device.dart
web_device.dart
```



而ios的实现是在 device.dart文件中的```IOSDevice```类，startApp函数删减后的内容如下

```
final String cpuArchitecture = await iMobileDevice.getInfoForDevice(id, 'CPUArchitecture');
      final DarwinArch iosArch = getIOSArchForName(cpuArchitecture);

      // Step 1: 编译app
      final XcodeBuildResult buildResult = await buildXcodeProject(
          app: package,
          buildInfo: debuggingOptions.buildInfo,
          targetOverride: mainPath,
          buildForDevice: true,
          usesTerminalUi: usesTerminalUi,
          activeArch: iosArch,
      );
      if (!buildResult.success) {
    } else {
      // 安装APP
      if (!await installApp(package))
        return LaunchResult.failed();
    }

    // Step 2: 检查.app文件是否存在指定目录
    final IOSApp iosApp = package;
    final Directory bundle = fs.directory(iosApp.deviceBundlePath);
    if (!bundle.existsSync()) {
      printError('Could not find the built application bundle at ${bundle.path}.');
      return LaunchResult.failed();
    }
    
    ProtocolDiscovery observatoryDiscovery;
    // 如果是debug或者profile模式，创建observatory server port
      if (debuggingOptions.debuggingEnabled) {
        printTrace('Debugging is enabled, connecting to observatory');

        observatoryDiscovery = ProtocolDiscovery.observatory(
          getLogReader(app: package),
          portForwarder: portForwarder,
          hostPort: debuggingOptions.observatoryPort,
          ipv6: ipv6,
        );
      }
      
    // Step 3: 尝试把包安装到设备上
      final int installationResult = await const IOSDeploy().runApp(
        deviceId: id,
        bundlePath: bundle.path,
        launchArguments: launchArguments,
      );
    try {
    } finally {
      installStatus.stop();
    }
```



1、获取iosArch: armv7  arm64 x86_64

2、执行buildXcodeProject方法，最终执行的脚本是：

```
/usr/bin/env xcrun xcodebuild -configuration=** -workspace =**  -sdk=iphoneos/iphonesimulator … 
```

以上命令，编译iOS工程并打包成ipa包

3、使用ios-deploy来安装并运行app到目标设备上

```
ios-deploy  --id = deviceId   --bundle = 项目目录/build/ios/iphoneos

说明：ios-deploy是一个终端安装和调试iPhone应用的是第三方开源库，安装应用到指定设备的命令是： ios-deploy --id [udid] --bundle [xxx.app]
```

4、对于debug或者profile模式<调试模式>，等待开启observatory服务



#### 一、xcodebuild编译iOS工程

Build phase中指定了一个脚本

```
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" build
```

那么，Xcode_backend.sh中做的事情是什么呢？

核心是：flutter build aot  & flutter build bundle

#####1、flutter build aot

也就是BuildAotCommand类：build_aot.dart

1)、KernelCompiler.compileKernel

编译dart文件，在项目目录/build/aot目录下产出以下文件：

```
kernel_compile.d
frontend_server.d
app.dill
```

编译dart文件执行的命令是：

```
flutter/bin/cache/dart-sdk/bin/dart
  flutter/bin/cache/artifacts/engine/darwin-x64/frontend_server.dart.snapshot
  --sdk-root flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk_product/
  --strong
  --target=flutter
  --aot --tfa
  -Ddart.vm.product=true
  --packages .packages
  --output-dill build/app/intermediates/flutter/release/app.dill
  --depfile     build/app/intermediates/flutter/release/kernel_compile.d
  package:项目目录/lib/main.dart
```



2)、遍历所有的arch：

对每一个arch进行AOTSnapshotter.build方法，而此方法的作用是，将dart kernel转换为AOT二进制机器码，比如在arm64架构下，命令如下

```
/usr/bin/arch -arm64 flutter/bin/cache/artifacts/engine/ios-release/gen_snapshot
  --causal_async_stacks
  --deterministic
  --snapshot_kind=app-aot-assembly
  --assembly=build/aot/arm64/snapshot_assembly.S //生成的文件
  build/aot/app.dill  //上一步编译dart产出的kernel文件
```

利用上一步得到的 snapshot_assembly.S文件，继续执行 xcrun cc命令，得到snapshot_assembly.o文件

```
xcrun cc 
-arch=armv7/arm64/x86_64 
-miphoneos-version-min=8.0
-fembed-bitcode 
-isysroot=iPhoneSDK的location 
-c = build/aot/目标arch目录下的snapshot_assembly.S 或者 assembly.stripped.S
-o = build/aot/目标arch目录下的snapshot_assembly.o
```

再利用snapshot_assembly.o文件，编译得到App.framework，编译的命令如下：

```
xcrun clang
-arch=armv7/arm64/x86_64 
-miphoneos-version-min=8.0
-dynamiclib
'-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
'-Xlinker', '-rpath', '-Xlinker', '@loader_path/Frameworks',
'-install_name', '@rpath/App.framework/App',
-fembed-bitcode
-isysroot=iPhoneSDK的location 
-o = 项目目录build/aot/目标arch目录下/App.framework/App
```

3)、使用lipo命令，把上一步中，生成的多个单arch的App.framework 合并成一个 多arch的App.framework

```
lipo  -create 
项目目录build/aot/arm64/App.framework
项目目录build/aot/armv7/App.framework
-o 项目目录build/aot/App.framework
```



综合以上所有的步骤，最终编译得到App.framework文件

##### 2、flutter build bundle

BuildBundleCommand

最终是把以下文件放入 flutter业务项目目录build/flutter_assets文件中

- AssetManifest.json

- FontManifest.json

- LICENSE

- fonts/MaterialIcons-Regular.ttf

- packages/cupertino_icons/assets/CupertinoIcons.ttf


##### xcode_backend.sh中剩下的内容

copy Flutter.framework  App.framework以及资源文件到Frameworks目录下等（待补充）



综上步骤，执行xcodebuild命令后，得到编译后的产物，再执行xcrun命令，打包成可安装的ipa包



#### 二、flutter install

InstallCommand

->  Device.installApp

如果有旧的安装包，就先删除旧的安装包，再执行安装

-> IOSDevice.installApp

执行命令 

bin/cache/artifacts/ideviceinstaller

-i  build/ios/iphoneos

执行命令后，把build/ios/iphoneos目录的Runner文件安装到目标设备上

ideviceinstaller如果有多台设备连接，需要-u参数执行设备id
