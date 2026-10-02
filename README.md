# 绘彩 HueCai

[![Build HueCai](https://github.com/MidSanCode/HueCai/actions/workflows/build.yml/badge.svg)](https://github.com/MidSanCode/HueCai/actions/workflows/build.yml)

简体中文 · [English](#english)

一款用 Flutter 编写的跨平台绘画应用，面向桌面与平板的手绘、上色与图像处理工作流。

> 本项目参考自 [Krita](https://krita.org/)。

---

## 功能

**绘画**
- 笔刷引擎：压感曲线编辑、笔迹稳定器（防抖 / 平滑 / 拉线）、颜料混合、喷雾 / 毛发 / 粒子笔尖
- 笔尖纹理：噪点、画布纹、网点、排线
- 辅助尺：直线、椭圆、样条，以及透视消失点吸附
- 矢量图层与路径编辑，文字沿路径排布

**图层**
- 图层编组（整体不透明度 / 混合模式、折叠展开）
- 图层蒙版、克隆图层、调整层（非破坏性滤镜）
- 20 种混合模式

**图像与颜色**
- 滤镜库 30 种：高斯模糊、USM 锐化、色阶、曲线、色相 / 饱和度、油画、半调、像素化、渐变映射、通道混合等
- 选区：羽化、收缩扩展、布尔运算（加 / 减 / 交）
- 高级色轮、调色板管理（支持 `.gpl` 导入）、色域警告

**动画与资源**
- 帧动画时间轴、洋葱皮、导出 GIF / PNG 序列
- 笔刷预设包与图案 / 纹理库导入导出、网点生成器

**扩展与同步**
- 脚本插件：行式 DSL + 沙盒执行器 + 脚本控制台（`.huescript`）
- WebDAV 云同步（含冲突处理）
- 界面辅助：笔刷 HUD、概览导航、快照对比、触控面板

## 文件格式

| 格式 | 说明 |
|------|------|
| `.hcproj` | 项目文件，采用 LGDF 标准格式 |
| `.ora` | 导入 / 导出（保留图层、不透明度、混合模式） |
| `.psd` | 压平导入 |
| `.gpl` | 调色板导入 |
| `.huebrush` / `.huepattern` / `.huescript` | 笔刷预设 / 图案 / 脚本插件包 |

## 平台

Windows · Linux（含 AppImage）· macOS · Android · iOS · Web

## 构建

需要 Flutter SDK（Dart SDK `^3.12.2`）。

```bash
flutter pub get
flutter run -d <device>
```

使用构建脚本打包（Windows）：

```powershell
.\build.ps1 -Platform windows    # windows | android | linux | macos | web
```

## 参与开发

```bash
flutter analyze   # 静态检查
flutter test      # 单元测试
```

功能实现进度见 [tasks.md](tasks.md)。

## 致谢

本项目参考自 [Krita](https://krita.org/)，一款优秀的开源绘画软件。

## 许可证

见 [LICENSE](LICENSE)。

---

## English

[简体中文](#绘彩-huecai) · English

A cross-platform painting application built with Flutter, aimed at desktop and tablet workflows for freehand drawing, coloring, and image processing.

> This project is inspired by [Krita](https://krita.org/).

### Features

**Painting**
- Brush engine: pressure curve editing, stroke stabilizer (anti-shake / smoothing / pull-string), pigment mixing, spray / bristle / particle tips
- Tip textures: noise, canvas grain, halftone dots, hatching
- Assist rulers: line, ellipse, spline, plus perspective vanishing-point snapping
- Vector layers with path editing, and text on a path

**Layers**
- Layer groups (group-wide opacity / blend mode, collapse & expand)
- Layer masks, cloned layers, adjustment layers (non-destructive filters)
- 20 blend modes

**Image & Color**
- 30 filters: Gaussian blur, USM sharpen, levels, curves, hue/saturation, oil paint, halftone, pixelate, gradient map, channel mixer, and more
- Selections: feather, grow/shrink, boolean operations (add / subtract / intersect)
- Advanced color wheel, palette management (`.gpl` import), gamut warning

**Animation & Assets**
- Frame animation timeline, onion skinning, GIF / PNG sequence export
- Brush preset and pattern/texture library import & export, halftone generator

**Extensibility & Sync**
- Script plugins: line-based DSL + sandboxed executor + script console (`.huescript`)
- WebDAV cloud sync with conflict handling
- UI helpers: brush HUD, overview navigation, snapshot comparison, touch panel

### File Formats

| Format | Description |
|--------|-------------|
| `.hcproj` | Project file, using the LGDF standard format |
| `.ora` | Import / export (layers, opacity, and blend modes preserved) |
| `.psd` | Flattened import |
| `.gpl` | Palette import |
| `.huebrush` / `.huepattern` / `.huescript` | Brush preset / pattern / script plugin packages |

### Platforms

Windows · Linux (including AppImage) · macOS · Android · iOS · Web

### Building

Requires the Flutter SDK (Dart SDK `^3.12.2`).

```bash
flutter pub get
flutter run -d <device>
```

Package with the build script (Windows):

```powershell
.\build.ps1 -Platform windows    # windows | android | linux | macos | web
```

### Development

```bash
flutter analyze   # static analysis
flutter test      # unit tests
```

See [tasks.md](tasks.md) for the feature roadmap and progress.

### Credits

This project is inspired by [Krita](https://krita.org/), an excellent open-source painting application.

### License

See [LICENSE](LICENSE).
