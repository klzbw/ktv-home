# HomeKTV iOS 客户端

基于 SwiftUI + WKWebView 的轻量级 iOS 客户端，包装家庭KTV的 H5 点歌页面。

## 功能

- 首次启动配置服务端地址
- 长按屏幕 1.5 秒进入设置页面
- 支持 iPhone 和 iPad
- 支持本地网络 HTTP 访问

## 使用方法

1. 安装应用后首次启动
2. 点击"配置服务端"
3. 输入服务端地址，例如：`192.168.1.100:8080`
4. 点击"保存并连接"
5. 应用会自动加载 `http://192.168.1.100:8080/m` 点歌页面

## 构建

使用 XcodeGen 生成 Xcode 项目：

```bash
cd ios
xcodegen generate
open HomeKTV.xcodeproj
```

## 系统要求

- iOS 15.0+
- Xcode 14.0+
