# ColorOS17 Type-C Headset Volume Fix

> 修复 ColorOS17 移植版（一加10 Pro）上 **Type-C 耳机音量无法调节、始终最大音量** 的问题。
>
> A KernelSU / Magisk module that fixes the "Type-C headset always plays at maximum
> volume, volume keys do nothing" bug on the ported ColorOS17 build for OnePlus 10 Pro.

---

## 问题现象 · Symptom

| | |
|---|---|
| 机型 | 一加10 Pro (NE2210 / `taro` / SM8450) |
| 系统 | ColorOS17 正式版 `NE2210_17.0.0.107(CN01)`（Android 17 / SDK 37）|
| 现象 | 插 Type-C 耳机后**以最大音量播放，音量键/音量条完全无效** |

音量条会动、`streamVolume` 会变，但**实际响度纹丝不动**。

---

## 根因 · Root cause

**移植的 framework 是 Android 17（SDK 37），它为 USB 耳机引入了新的设备类别
`DEVICE_CATEGORY_USB_HEADSET`；而 vendor 的 `audio_policy_volumes.xml` 来自
Android 16（SDK 36），没有这个类别 → 音量曲线查表失败 → 回退到平坦曲线
`FULL_SCALE_VOLUME_CURVE`（每一档都是 `0 dB`）→ 混音器永远单位增益。**

### 直接证据

框架的类别表（`/system/lib64/libaudiopolicycomponents.so` 字符串表中存在）：

```
DEVICE_CATEGORY_EARPIECE
DEVICE_CATEGORY_EXT_MEDIA
DEVICE_CATEGORY_HEADSET
DEVICE_CATEGORY_HEARING_AID
DEVICE_CATEGORY_SPEAKER
DEVICE_CATEGORY_USB_HEADSET          ← Android 17 新增
```

vendor 的曲线表（`/vendor/etc/audio_policy_volumes.xml`）：

```
DEVICE_CATEGORY_EARPIECE / EXT_MEDIA / HEADSET / HEARING_AID / SPEAKER
                                     ← 缺 USB_HEADSET
```

查不到曲线时使用的兜底表：

```xml
<reference name="FULL_SCALE_VOLUME_CURVE">
    <point>0,0</point>        <!-- 索引 0   -> 0 dB -->
    <point>100,0</point>      <!-- 索引 100 -> 0 dB -->
</reference>
```

实测佐证（`dumpsys media.audio_flinger`，USB 输出线程上的活跃 track）：

| STREAM_MUSIC 索引 | track 增益 (G/L/R/VS dB) |
|---|---|
| 0（最小） | `0, 0, 0, 0` |
| 50 | `0, 0, 0, 0` |
| 100 | `0, 0, 0, 0` |

**索引在变，增益恒为 0 dB（单位增益 = 满幅）。**

---

## 修复原理 · What the module does

把 `audio_policy_volumes.xml` 里 **14 条 `DEVICE_CATEGORY_HEADSET` 曲线各复制一份**，
类别改成 `DEVICE_CATEGORY_USB_HEADSET`，写回 14 条新曲线：

```
volume 条目总数: 84   HEADSET: 14   USB_HEADSET: 14   ✅ 数量匹配
```

**不碰路由、不碰属性、不碰 HAL** —— 音频输出行为完全不受影响。

生效方式（双保险）：

1. `system/vendor/etc/audio_policy_volumes.xml` —— 模块覆盖层
2. `post-fs-data.sh` —— `mount --bind` 显式覆盖，并用 `chcon --reference`
   继承目标文件的 SELinux 上下文（否则 audioserver 读不到）

---

## 安装 · Install

需要 **KernelSU / SukiSU / Magisk**（本机验证环境为 SukiSU v4.1.3，内核驱动 40796）。

1. 下载 [Releases](../../releases) 里的 `c17_usb_volume_fix-vX.Y.zip`
2. 打开 root 管理器 → **模块** → 右下角 **＋** → 选择 zip
3. **重启手机**

### 验证是否生效

```sh
adb shell cat /data/local/tmp/c17_usb_volume_fix.log
# 应看到: VERIFY OK: 14 USB_HEADSET curves present

adb shell grep -c DEVICE_CATEGORY_USB_HEADSET /vendor/etc/audio_policy_volumes.xml
# 应输出: 14
```

### 卸载 · Uninstall

管理器 → 模块 → 关闭开关（或卸载）→ 重启。**原始配置一字未改**，关掉即恢复。

---

## 适用性 · Compatibility

本模块的配置**只适用于该移植包的 SKU 音频配置**。判断你的机器是否适用：

```sh
# 若这条命令有输出，说明框架使用了新类别而 vendor 缺曲线 —— 本模块适用
adb shell strings /system/lib64/libaudiopolicycomponents.so | grep DEVICE_CATEGORY_USB_HEADSET
adb shell grep -c DEVICE_CATEGORY_USB_HEADSET /vendor/etc/audio_policy_volumes.xml   # 0 = 缺
```

其它移植包如果也是「新框架 + 旧 vendor 配置」的组合，同样会遇到这个 bug；
但**曲线参数需按各自设备调整**，不要直接套用。

---

## 三次失败尝试（重要留档）

定位过程中试过三个方向，全部失败 —— 记录下来避免他人重走：

| 尝试 | 做法 | 结果 | 为什么错 |
|---|---|---|---|
| **v1** | 把 USB 输出从 primary HAL 改回官方 520 的专用 `usb` HAL 路由 | ❌ **耳机完全没声** | 官方 520 确实用专用 `usb` HAL（`USB Headset Out ← usb_device output`），但**移植版的 `audio.usb.default.so` 推不出声** —— 移植者把 USB 改道 primary HAL 是**必要改动**，不是 bug |
| **v2** | 保留 primary 路由，只从 USB 路由摘掉直通路径（`hifi_playback` / `compressed_offload` / `direct_pcm` / `raw` / `mmap_no_irq_out`） | ❌ 声音正常但仍无效 | 实测活跃线程本来就是 `MIXER + AUDIO_OUTPUT_FLAG_DEEP_BUFFER` 纯混音路径，直通路径根本不是病因 |
| **v3** | `resetprop` 关掉 `ro.oplus.audio.aidl_volume` 与无级音量、写回 `config.media_vol_steps=25` | ❌ 属性确实生效（`Max` 160→25）但仍无效 | 说明 OPPO 自研音量通道也不是病因 —— **连标准 AOSP 链路也失效**，问题在更底层的曲线查表 |
| **v4** | 补 `DEVICE_CATEGORY_USB_HEADSET` 曲线 | ✅ **修复** | — |

**教训**：这类现象在框架里有多个可能环节 —— 路由、音量通道、曲线表。
前三次都在改前两个，而缺的是**一整个类别**。
定位的关键动作是：**对比「框架认识的枚举值」与「配置文件里定义的枚举值」**。

---

## 给 ROM 作者的建议

这是移植时 **framework(SDK 37) 与 vendor 配置(SDK 36) 版本错配** 的典型问题，
会影响所有走 `AUDIO_DEVICE_OUT_USB_HEADSET` 的场景（Type-C 耳机、部分转接头）。

**比模块更彻底的正解**：把 `DEVICE_CATEGORY_USB_HEADSET` 的曲线直接合并进
打包的 `vendor/etc/audio_policy_volumes.xml`，或确认移植时选用的 SKU 音频配置
与框架版本匹配。同时建议检查 `DEVICE_CATEGORY_` 下其它新增枚举是否也受影响。

---

## 调试环境备注（复现同类问题的坑）

- **手机只有一个 Type-C 口**：插耳机 = USB adb 断开。全程靠 `adb tcpip 5555`
  无线 adb 调试；重生后 `tcpip` 模式会失效，需再用 USB 重开一次。
- **SukiSU v4.1.3 的模块安装按钮（右下角 +）无法用 adb 注入点击**：
  `input tap` / `swipe` / `motionevent` / D-pad 全无效（Jetpack Compose 渲染，
  不在 accessibility 树里）。装模块必须手动点屏幕。
- **TWRP 读不到 `/data`**（FBE 加密），无法用 TWRP 走 CLI 装模块。
- **adb 服务端可能因 `%TEMP%` 权限起不来**：先设置可写 TEMP 再 `adb start-server`。
- **/proc/asound 对 shell 用户是拒绝访问的**，探测 USB 声卡要换用
  `dumpsys audio` 里的 `setWiredDeviceConnectionState(type:4000000 ...)` 事件。

---

## License

[MIT](LICENSE)

本项目只包含**配置数据**，不含任何原厂二进制文件。
