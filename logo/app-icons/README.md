# Home KTV App Icons

家庭 KTV 系统多平台 App 图标资源包。

## 设计说明

- **主题**: 家庭 KTV（Home KTV）
- **主视觉**: 白色线条风格的房子轮廓 + 内置麦克风 + 屋顶音符
- **背景渐变**: 暖橙 `#ff8a2b` → 玫红 `#ff315f` → 深紫 `#17133b`
- **风格**: 扁平化、极简、高对比度，小尺寸下仍清晰可辨
- **圆角**: iOS 风格圆角方形（系统会自动裁剪为对应形状）

## 目录结构

```
app-icons/
├── master/
│   └── app-icon-1024.png          # 主图标 1024x1024（所有尺寸的源文件）
├── ios/
│   ├── AppIcon.appiconset/        # iOS 资源目录（可直接拖入 Xcode）
│   │   ├── Contents.json
│   │   └── *.png                  # iPhone/iPad 各尺寸 + App Store 1024
│   └── (单独尺寸文件)
├── tvos/
│   ├── tvos-icon-464.png          # tvOS 图标 @1x
│   ├── tvos-icon-928.png          # tvOS 图标 @2x
│   ├── tvos-top-shelf-400x240.png
│   ├── tvos-top-shelf-1280x768.png
│   └── tvos-top-shelf-2320x720.png
├── android/
│   ├── mipmap-anydpi-v26/         # 自适应图标（Android 8.0+）
│   │   ├── ic_launcher.xml
│   │   └── ic_launcher_round.xml
│   ├── mipmap-mdpi/  ic_launcher.png (48px)
│   ├── mipmap-hdpi/  ic_launcher.png (72px)
│   ├── mipmap-xhdpi/ ic_launcher.png (96px)
│   ├── mipmap-xxhdpi/ ic_launcher.png (144px)
│   ├── mipmap-xxxhdpi/ ic_launcher.png (192px)
│   ├── values/ic_launcher_background.xml
│   └── play-store-512.png          # Google Play 商店图标
└── web/
    ├── favicon-16.png
    ├── favicon-32.png
    ├── favicon-48.png
    ├── apple-touch-57.png ~ 180.png
    └── (iOS 主屏幕添加到桌面图标)
```

## 集成指南

### iOS

1. 将 `ios/AppIcon.appiconset/` 目录整体复制到 Xcode 项目的 `Assets.xcassets/` 中
2. 在 Target → General → App Icons 中选择 `AppIcon`
3. 如需在 XcodeGen (`project.yml`) 中配置，确保资源路径包含该目录

### tvOS

1. 将 `tvos/` 下的图标文件添加到 tvOS Target 的 Asset Catalog
2. Top Shelf 图片用于 Apple TV 主屏幕顶部展示

### Android

1. 将 `android/mipmap-*/` 和 `android/mipmap-anydpi-v26/` 目录复制到 `app/src/main/res/`
2. 将 `android/values/ic_launcher_background.xml` 复制到 `app/src/main/res/values/`
3. 在 `AndroidManifest.xml` 中确认 `android:icon="@mipmap/ic_launcher"` 和 `android:roundIcon="@mipmap/ic_launcher_round"`

### Web / H5

1. 将 `web/favicon-32.png` 重命名为 `favicon.ico` 或直接引用为 PNG
2. 在 HTML `<head>` 中添加：
   ```html
   <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
   <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-180.png">
   ```

## 尺寸对照表

| 平台 | 用途 | 尺寸 (px) |
|------|------|-----------|
| iOS | iPhone App (@3x) | 180×180 |
| iOS | iPhone App (@2x) | 120×120 |
| iOS | iPad App (@2x) | 152×152 |
| iOS | iPad Pro App | 167×167 |
| iOS | App Store | 1024×1024 |
| tvOS | App Icon (@2x) | 928×928 |
| tvOS | Top Shelf | 2320×720 |
| Android | xxxhdpi | 192×192 |
| Android | xxhdpi | 144×144 |
| Android | xhdpi | 96×96 |
| Android | Play Store | 512×512 |
