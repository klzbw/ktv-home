# 家庭KTV tvOS 客户端

可侧载的Apple TV应用，使用WKWebView包装H5点歌页面。

## 功能

- 局域网服务端配置
- 全屏点歌页面
- tvOS遥控器支持
- 长按设置键1.5秒进入配置页面

## 系统要求

- Apple TV (tvOS 15.0+)
- 家庭KTV服务端运行在局域网内

## 构建

### 使用GitHub Actions自动构建

推送代码到 `master` 或 `main` 分支，或手动触发 `tvOS Build IPA` 工作流，即可自动构建IPA。

### 本地构建

需要macOS和Xcode：

```bash
cd tvos
brew install xcodegen
xcodegen generate
xcodebuild -project HomeKTV.xcodeproj -scheme HomeKTV -configuration Release -destination 'generic/platform=tvOS' -archivePath build/HomeKTV.xcarchive archive CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
mkdir -p build/Payload
cp -R build/HomeKTV.xcarchive/Products/Applications/HomeKTV.app build/Payload/
cd build && zip -r HomeKTV-tvOS.ipa Payload
```

## 侧载安装

### 使用Sideloadly（推荐）

1. 下载 [Sideloadly](https://sideloadly.io/)
2. 连接Apple TV到电脑（或使用Wi-Fi）
3. 拖入IPA文件
4. 输入Apple ID（免费账户可用，7天过期）
5. 点击Start开始安装

### 使用AltStore

1. 安装 [AltStore](https://altstore.io/) 到Apple TV
2. 在AltStore中添加IPA文件
3. 使用Apple ID签名安装

## 使用说明

1. 首次启动后，长按遥控器设置键1.5秒进入配置页面
2. 输入家庭KTV服务端地址，例如：`192.168.1.100:8080`
3. 点击"保存并连接"
4. 应用会自动加载点歌页面

## 项目结构

```
tvos/
├── HomeKTV/
│   ├── HomeKTVApp.swift      # 应用入口
│   ├── ContentView.swift      # 主视图（WKWebView）
│   ├── ServerConfig.swift     # 服务端配置管理
│   ├── SettingsView.swift     # 设置页面
│   └── Info.plist             # 应用配置
├── project.yml                 # XcodeGen配置
└── README.md
```
