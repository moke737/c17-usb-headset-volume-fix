#!/system/bin/sh
ui_print "- ColorOS17 Type-C 耳机音量修复 v4"
ui_print "  给音量曲线表补上 DEVICE_CATEGORY_USB_HEADSET"
ui_print "  （框架是 Android 17，vendor 曲线表是 Android 16，缺这个新类别）"
ui_print "  只覆盖 audio_policy_volumes.xml，不动路由与属性"
ui_print "  安装后请重启手机"