## flutter run机制



首先，有两个目录：

flutter仓库目录：从flutter的git仓库 clone下来的本地目录

项目目录：创建的应用的目录

创建应用命令如下：

```
flutter create ****(项目名)

这个flutter: 是在系统的环境变量中设置的目录下的flutter可执行文件
export PATH=/Users/chunhongwang/install/flutter/bin:$PATH
```

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

查看```flutter_tools.dart```文件，内容如下，也就是执行到```executable.dart```文件

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

综上过程，执行的flutter命令的实现都在 flutter仓库/bin/packages/flutter_tools目录里。

###flutter create *(项目名) 命令

```CreateCommand```，主要工作是就是：创建项目目录，以及安卓和ios的工程，以及默认的```lib/main.dart```

###flutter run ios

```run.dart中的RunCommand类```

```dart
//找到所有的目标设备
devices = await findAllTargetDevices();

//以下三种分别是是什么？？？
如果是 hotMode && !webMode:
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
    if (!prebuiltApplication) {
      //如果没有预编译好，先执行编译
      final XcodeBuildResult buildResult = await buildXcodeProject(
          app: package,
          buildInfo: debuggingOptions.buildInfo,
          targetOverride: mainPath,
          buildForDevice: true,
          usesTerminalUi: usesTerminalUi,
          activeArch: iosArch,
      );
    } else {
      // 已经编译好的，直接安装APP
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
      
    // Step 3: 尝试在设备上运行调试
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

2、编译app，生成ipa包，执行buildXcodeProject方法，最终执行的脚本是：

```
/usr/bin/env xcrun xcodebuild -configuration=** -workspace =**  -sdk=iphoneos/iphonesimulator … 
```

以上命令，编译iOS工程并打包成ipa包

3、使用ios-deploy来安装并运行app到目标设备上

4、对于debug或者profile模式<调试模式>，等待开启observatory服务



#### 一、编译app：xcodebuild编译iOS工程

Build phase中指定了一个脚本

```
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" build
```

那么，Xcode_backend.sh中做的事情是什么呢？

核心是：flutter build aot  & flutter build bundle

#####1、flutter build aot

也就是BuildAotCommand类：build_aot.dart，这个类做的事情主要有以下三步

1）KernelCompiler.compileKernel

先编译dart文件，编译后得到app.dill，其中编译dart文件执行的命令是：

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

由上诉命令可以看出，主要是使用前端编译器frontend_server进行编译的，它的主要工作是先将项目的dart代码转换成AST（抽象语法树），再将整理dart代码得到Component对象的内容，执行全局的混淆等转换工作后，写入app.dill文件中。

而Component的成员变量主要有以下三个：

- libraries：记录所有的lib库，包括app源文件、package以及第三方库，每个Library对象有Class、Field、procedure等组成
- uriToSource：类型为Map<Uri, Source>，用于从源文件URI映射到line-starts表和源代码，给定一个源文件URI和该文件中的偏移量，就可以转换为该文件中line：column的位置
- _mainMethodName：main方法的文件的URI，可通过这个找到main方法的入口

此编译工作结束后，会在项目目录/build/aot目录下写入以下文件：

```
kernel_compile.d
frontend_server.d
app.dill  //主要是产出此文件，包含了dart代码的信息
```



2）kernel文件转换成机器码

遍历所有的arch：

对每一个arch进行AOTSnapshotter.build方法，而此方法的作用是，将dart代码生成AOT二进制机器码，文件类型是app-aot-assembly，比如在arm64架构下，命令如下

```
/usr/bin/arch -arm64 flutter/bin/cache/artifacts/engine/ios-release/gen_snapshot
  --causal_async_stacks
  --deterministic
  --snapshot_kind=app-aot-assembly
  --assembly=build/aot/arm64/snapshot_assembly.S //生成的文件
  build/aot/app.dill  //上一步编译dart产出的kernel文件
```

gen_snapshot是dart runtime目录下的一个多体系结构二进制文件，所对应的执行方法源码为third_party/dart/runtime/bin/gen_snapshot.cc，gen_snapshot将dart代码生成AOT二进制机器码。 作为i386二进制文件运行将生成armv7代码， 作为x86_64二进制文件运行将生成arm64代码。

它的工作的主要内容是:

- 先执行Dart_Initialize()来初始化Dart虚拟机环境
- 再执行CreateIsolateAndSnapshot ：此方法中，针对不同的模式，会调用不同的方法，创建相应的产物，方法如下
  - kCore：CreateAndWriteCoreSnapshot
  - kCoreJIT：CreateAndWriteCoreJITSnapshot
  - kApp：CreateAndWriteAppSnapshot
  - kAppJIT：CreateAndWriteAppJITSnapshot
  - kAppAOTBlobs：CreateAndWritePrecompiledSnapshot
  - kAppAOTAssembly：CreateAndWritePrecompiledSnapshot
  - kVMAOTAssembly：Dart_CreateVMAOTSnapshotAsAssembly

在AOT模式下，iOS的类型为kAppAOTAssembly，安卓的为kAppAOTBlobs，调用的方法都是CreateAndWritePrecompiledSnapshot，而方法的工作就是

1、执行AOT编译

2、得到snapshot代码写入buffer，

3、再将buffer写入四个二进制文件vm_snapshot_data（vm的数据段），vm_snapshot_instructions（vm的代码段），isolate_snapshot_data（isolate的数据段），isolate_snapshot_instructions（isolate的代码段）。



以上AOT快照编译得到的机器码写入的是 snapshot_assembly.S文件？？？

3）依旧是在每一个arch的每一个遍历步骤中，得到机器码后，最终编译为特定框架的App.framework，过程如下：

利用 snapshot_assembly.S文件，继续执行 xcrun -cc -c命令，进行预处理、编译以及汇编，得到snapshot_assembly.o文件

```
xcrun -cc 
-arch=armv7/arm64/x86_64 
-miphoneos-version-min=8.0
-fembed-bitcode 
-isysroot=iPhoneSDK的location 
-c = build/aot/目标arch目录下的snapshot_assembly.S 或者 assembly.stripped.S
-o = build/aot/目标arch目录下的snapshot_assembly.o
```

再执行Link（链接），把多个二进制文件对象链接成单一的可执行文件

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



4）使用lipo命令，把上一步中，生成的多个单框架的App.framework 合并成一个 多框架的App.framework

```
lipo  -create 
项目目录build/aot/arm64/App.framework
项目目录build/aot/armv7/App.framework
-o 项目目录build/aot/App.framework
```



综合以上所有的步骤，总结起来就是先编译项目中的dart代码得到  最终编译得到kernel文件，再针对每一个arch编译成对应的机器码，最终得到 App.framework文件

##### 2、flutter build bundle

BuildBundleCommand

最终是把以下文件放入 flutter业务项目目录build/flutter_assets文件中

- AssetManifest.json

- FontManifest.json

- LICENSE

- fonts/MaterialIcons-Regular.ttf

- packages/cupertino_icons/assets/CupertinoIcons.ttf


##### 3、xcode_backend.sh中剩下的内容

copy Flutter.framework  App.framework以及资源文件到目标目录下等（待补充）



综上步骤，执行xcodebuild命令后，得到编译后的产物，再执行xcrun命令，打包成可安装的ipa包



#### 二、安装app：IOSDevice.installApp

其实```flutter install```的命令也是最终调用的IOSDevice.installApp

->  Device.installApp

如果有旧的安装包，就先删除旧的安装包，再执行安装

-> IOSDevice.installApp

执行命令 

bin/cache/artifacts/ideviceinstaller

-i  build/ios/iphoneos

执行命令后，把build/ios/iphoneos目录的Runner文件安装到目标设备上

ideviceinstaller如果有多台设备连接，需要-u参数执行设备id



#### 三、运行调试app：ios-deploy

```
ios-deploy  --id = deviceId   --bundle = 项目目录/build/ios/iphoneos

说明：ios-deploy是一个终端安装和调试iPhone应用的是第三方开源库，安装应用到指定设备的命令是： ios-deploy --id [udid] --bundle [xxx.app]
```

