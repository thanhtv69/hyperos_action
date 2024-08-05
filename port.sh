#!/bin/bash

# hyperOS_port project

# For A-only and V/A-B (not tested) Devices

# Based on Android 13

# Test Base ROM: A-only Mi 10/PRO/Ultra (MIUI 14 Latset stockrom)

# Test Port ROM: Mi 14/Pro OS1.0.9-1.0.25 Mi 13/PRO OS1.0 23.11.09-23.11.10 DEV


build_user="Bruce Teng"
build_host=$(hostname)

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$PATH

# Import functions
source functions.sh

shopt -s expand_aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    yellow "检测到Mac，设置alias" "macOS detected,setting alias"
    alias sed=gsed
    alias tr=gtr
    alias grep=ggrep
    alias du=gdu
    alias date=gdate
    #alias find=gfind
fi


check unzip aria2c 7z zip java zipalign python3 zstd bc xmlstarlet

# 移植的分区，可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
#super_list=$(grep "super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
brightness_fix_method=$(grep "brightness_fix_method" bin/port_config |cut -d '=' -f 2)

compatible_matrix_matches_enabled=$(grep "compatible_matrix_matches_check" bin/port_config | cut -d '=' -f 2)

if [[ ${repackext4} == true ]]; then
    pack_type=EXT
else
    pack_type=EROFS
fi


# 检查为本地包还是链接
if [ ! -f "${baserom}" ] && [ "$(echo $baserom |grep http)" != "" ];then
    blue "底包为一个链接，正在尝试下载" "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${baserom}
    baserom=$(basename ${baserom} | sed 's/\?t.*//')
    if [ ! -f "${baserom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${baserom}" ];then
    green "底包: ${baserom}" "BASEROM: ${baserom}"
else
    error "底包参数错误" "BASEROM: Invalid parameter"
    exit
fi

if [ ! -f "${portrom}" ] && [ "$(echo ${portrom} |grep http)" != "" ];then
    blue "移植包为一个链接，正在尝试下载"  "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${portrom}
    portrom=$(basename ${portrom} | sed 's/\?t.*//')
    if [ ! -f "${portrom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${portrom}" ];then
    green "移植包: ${portrom}" "PORTROM: ${portrom}"
else
    error "移植包参数错误" "PORTROM: Invalid parameter"
    exit
fi

if [ "$(echo $baserom |grep miui_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
elif [ "$(echo $baserom |grep xiaomi.eu_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 3)
else
    device_code="YourDevice"
fi

blue "正在检测ROM底包" "Validating BASEROM.."
if unzip -l ${baserom} | grep -q "payload.bin"; then
    baserom_type="payload"
    super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
elif unzip -l ${baserom} | grep -q "br$";then
    baserom_type="br"
    super_list="vendor mi_ext odm system product system_ext"
elif unzip -l ${baserom} | grep -q "images/super.img*"; then
    is_base_rom_eu=true
    super_list="vendor mi_ext odm system product system_ext"
else
    error "底包中未发现payload.bin以及br文件，请使用MIUI官方包后重试" "payload.bin/new.br not found, please use HyperOS official OTA zip package."
    exit
fi

blue "开始检测ROM移植包" "Validating PORTROM.."
if unzip -l ${portrom} | grep  -q "payload.bin"; then
    green "ROM初步检测通过" "ROM validation passed."
elif [[ ${portrom} == *"xiaomi.eu"* ]];then
    is_eu_rom=true
else
    error "目标移植包没有payload.bin，请用MIUI官方包作为移植包" "payload.bin not found, please use HyperOS official OTA zip package."
fi

green "ROM初步检测通过" "ROM validation passed."

if [[ "$portrom" =~ SHENNONG|HOUJI ]]; then
    is_shennong_houji_port=true
else
    is_shennong_houji_port=false
fi

blue "正在清理文件" "Cleaning up.."
for i in ${port_partition};do
    [ -d ./${i} ] && rm -rf ./${i}
done
sudo rm -rf app
sudo rm -rf tmp
sudo rm -rf out/
sudo rm -rf config
sudo rm -rf build/baserom/
sudo rm -rf build/portrom/
find . -type d -name 'hyperos_*' |xargs rm -rf

green "文件清理完毕" "Files cleaned up."
mkdir -p build/baserom/images/

mkdir -p build/portrom/images/


# 提取分区
if [[ ${baserom_type} == 'payload' ]];then
    blue "正在提取底包 [payload.bin]" "Extracting files from BASEROM [payload.bin]"
    unzip ${baserom} payload.bin -d build/baserom > /dev/null 2>&1 ||error "解压底包 [payload.bin] 时出错" "Extracting [payload.bin] error"
    green "底包 [payload.bin] 提取完毕" "[payload.bin] extracted."
elif [[ ${baserom_type} == 'br' ]];then
    blue "正在提取底包 [new.dat.br]" "Extracting files from BASEROM [*.new.dat.br]"
    unzip ${baserom} -d build/baserom  > /dev/null 2>&1 || error "解压底包 [new.dat.br]时出错" "Extracting [new.dat.br] error"
    green "底包 [new.dat.br] 提取完毕" "[new.dat.br] extracted."
elif [[ ${is_base_rom_eu} == true ]];then
    blue "正在提取底包 [super.img]" "Extracting files from BASETROM [super.img]"
    unzip ${baserom} 'images/*' -d build/baserom >  /dev/null 2>&1 ||error "解压移植包 [super.img] 时出错"  "Extracting [super.img] error"
    blue "合并super.img* 到super.img" "Merging super.img.* into super.img"
    simg2img build/baserom/images/super.img.* build/baserom/images/super.img
    rm -rf build/baserom/images/super.img.*
    mv build/baserom/images/super.img build/baserom/super.img
    green "底包 [super.img] 提取完毕" "[super.img] extracted."
    mv build/baserom/images/boot.img build/baserom/
    mkdir -p build/baserom/firmware-update
    mv build/baserom/images/* build/baserom/firmware-update
    if [[ -f build/baserom/firmware-update/cust.img.0 ]];then
        simg2img build/baserom/firmware-update/cust.img.* build/baserom/firmware-update/cust.img
        rm -rf build/baserom/firmware-update/cust.img.*
    fi
fi

if [[ ${is_eu_rom} == true ]];then
    blue "正在提取移植包 [super.img]" "Extracting files from PORTROM [super.img]"
    unzip ${portrom} 'images/super.img.*' -d build/portrom >  /dev/null 2>&1 ||error "解压移植包 [super.img] 时出错"  "Extracting [super.img] error"
    blue "合并super.img* 到super.img" "Merging super.img.* into super.img"
    simg2img build/portrom/images/super.img.* build/portrom/images/super.img
    rm -rf build/portrom/images/super.img.*
    mv build/portrom/images/super.img build/portrom/super.img
    green "移植包 [super.img] 提取完毕" "[super.img] extracted."
else
    blue "正在提取移植包 [payload.bin]" "Extracting files from PORTROM [payload.bin]"
    unzip ${portrom} payload.bin -d build/portrom  > /dev/null 2>&1 ||error "解压移植包 [payload.bin] 时出错"  "Extracting [payload.bin] error"
    green "移植包 [payload.bin] 提取完毕" "[payload.bin] extracted."
fi

if [[ ${baserom_type} == 'payload' ]];then

    blue "开始分解底包 [payload.bin]" "Unpacking BASEROM [payload.bin]"
    payload-dumper-go -o build/baserom/images/ build/baserom/payload.bin >/dev/null 2>&1 ||error "分解底包 [payload.bin] 时出错" "Unpacking [payload.bin] failed"

elif [[ ${is_base_rom_eu} == true ]];then
     blue "开始分解底包 [super.img]" "Unpacking BASEROM [super.img]"
        for i in ${super_list}; do
            python3 bin/lpunpack.py -p ${i} build/baserom/super.img build/baserom/images
        done

elif [[ ${baserom_type} == 'br' ]];then
    blue "开始分解底包 [new.dat.br]" "Unpacking BASEROM[new.dat.br]"
        for i in ${super_list}; do
            ${tools_dir}/brotli -d build/baserom/$i.new.dat.br
            sudo python3 ${work_dir}/bin/sdat2img.py build/baserom/$i.transfer.list build/baserom/$i.new.dat build/baserom/images/$i.img >/dev/null 2>&1
            rm -rf build/baserom/$i.new.dat* build/baserom/$i.transfer.list build/baserom/$i.patch.*
        done
fi

for part in system system_dlkm system_ext product product_dlkm mi_ext ;do
    if [[ -f build/baserom/images/${part}.img ]];then
        if [[ $(python3 $work_dir/bin/gettype.py build/baserom/images/${part}.img) == "ext" ]];then
            blue "正在分解底包 ${part}.img [ext]" "Extracing ${part}.img [ext] from BASEROM"
            sudo python3 bin/imgextractor/imgextractor.py build/baserom/images/${part}.img build/baserom/images/
            blue "分解底包 [${part}.img] 完成" "BASEROM ${part}.img [ext] extracted."
            rm -rf build/baserom/images/${part}.img
        elif [[ $(python3 $work_dir/bin/gettype.py build/baserom/images/${part}.img) == "erofs" ]]; then
            pack_type=EROFS
            blue "正在分解底包 ${part}.img [erofs]" "Extracing ${part}.img [erofs] from BASEROM"
            extract.erofs -x -i build/baserom/images/${part}.img  -o build/baserom/images/ || error "分解 ${part}.img 失败" "Extracting ${part}.img failed."
            blue "分解底包 [${part}.img][erofs] 完成" "BASEROM ${part}.img [erofs] extracted."
            rm -rf build/baserom/images/${part}.img
        fi
    fi

done

for image in vendor odm vendor_dlkm odm_dlkm;do
    if [ -f build/baserom/images/${image}.img ];then
        cp -rf build/baserom/images/${image}.img build/portrom/images/${image}.img
    fi
done

# 分解镜像
green "开始提取逻辑分区镜像" "Starting extract partition from img"
echo $super_list
for part in ${super_list};do
    if [[ $part =~ ^(vendor|odm|vendor_dlkm|odm_dlkm)$ ]] && [[ -f "build/portrom/images/$part.img" ]]; then
        blue "从底包中提取 [${part}]分区 ..." "Extracting [${part}] from BASEROM"
    else
        if [[ ${is_eu_rom} == true ]];then
            blue "PORTROM super.img 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM super.img"
            blue "lpunpack.py PORTROM super.img ${patrt}_a"
            python3 bin/lpunpack.py -p ${part}_a build/portrom/super.img build/portrom/images
            mv build/portrom/images/${part}_a.img build/portrom/images/${part}.img
        else
            blue "payload.bin 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM payload.bin"
            payload-dumper-go -p ${part} -o build/portrom/images/ build/portrom/payload.bin >/dev/null 2>&1 ||error "提取移植包 [${part}] 分区时出错" "Extracting partition [${part}] error."
        fi
    fi
    if [ -f "${work_dir}/build/portrom/images/${part}.img" ];then
        blue "开始提取 ${part}.img" "Extracting ${part}.img"

        if [[ $(python3 $work_dir/bin/gettype.py build/portrom/images/${part}.img) == "ext" ]];then
            pack_type=EXT
            python3 bin/imgextractor/imgextractor.py build/portrom/images/${part}.img build/portrom/images/ || error "提取${part}失败" "Extracting partition ${part} failed"
            mkdir -p build/portrom/images/${part}/lost+found
            rm -rf build/portrom/images/${part}.img
            green "提取 [${part}] [ext]镜像完毕" "Extracting [${part}].img [ext] done"
        elif [[ $(python3 $work_dir/bin/gettype.py build/portrom/images/${part}.img) == "erofs" ]];then
            pack_type=EROFS
            green "移植包为 [erofs] 文件系统" "PORTROM filesystem: [erofs]. "
            [ "${repackext4}" = "true" ] && pack_type=EXT
            extract.erofs -x -i build/portrom/images/${part}.img -o build/portrom/images/ || error "提取${part}失败" "Extracting ${part} failed"
            mkdir -p build/portrom/images/${part}/lost+found
            rm -rf build/portrom/images/${part}.img
            green "提取移植包[${part}] [erofs]镜像完毕" "Extracting ${part} [erofs] done."
        fi

    fi
done
rm -rf config

blue "正在获取ROM参数" "Fetching ROM build prop."

# 安卓版本
base_android_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.incremental" |awk 'NR==1' |cut -d '=' -f 2)

#HyperOS版本号获取
port_mios_version_incremental=$(< build/portrom/images/mi_ext/etc/build.prop grep "ro.mi.os.version.incremental" | awk 'NR==1' | cut -d '=' -f 2)
#替换机型代号,比如小米10：UNBCNXM -> UJBCNXM

port_device_code=$(echo $port_mios_version_incremental | cut -d "." -f 5)

if [[ $port_mios_version_incremental == *DEV* ]];then
    yellow "检测到开发板，跳过修改版本代码" "Dev deteced,skip replacing codename"
    port_rom_version=$(echo $port_mios_version_incremental)
else
    base_device_code=U$(echo $base_rom_version | cut -d "." -f 5 | cut -c 2-)
    port_rom_version=$(echo $port_mios_version_incremental | sed "s/$port_device_code/$base_device_code/")
fi
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]" "ROM Version: BASEROM: [${base_rom_version}], PORTROM: [${port_rom_version}] "

# 代号
base_rom_code=$(< build/portrom/images/vendor/build.prop grep "ro.product.vendor.device" |awk 'NR==1' |cut -d '=' -f 2)
port_rom_code=$(< build/portrom/images/product/etc/build.prop grep "ro.product.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]" "Device Code: BASEROM: [${base_rom_code}], PORTROM: [${port_rom_code}]"

if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi
for cpfile in "AospFrameworkResOverlay.apk" "MiuiFrameworkResOverlay.apk" "DevicesAndroidOverlay.apk" "DevicesOverlay.apk" "SettingsRroDeviceHideStatusBarOverlay.apk" "MiuiBiometricResOverlay.apk"
do
  base_file=$(find build/baserom/images/product -type f -name "$cpfile")
  port_file=$(find build/portrom/images/product -type f -name "$cpfile")
  if [ -f "${base_file}" ] && [ -f "${port_file}" ];then
    blue "正在替换 [$cpfile]" "Replacing [$cpfile]"
    cp -rf ${base_file} ${port_file}
  fi
done

#baseAospWifiResOverlay=$(find build/baserom/images/product -type f -name "AospWifiResOverlay.apk")
##portAospWifiResOverlay=$(find build/portrom/images/product -type f -name "AospWifiResOverlay.apk")
#if [ -f ${baseAospWifiResOverlay} ] && [ -f ${portAospWifiResOverlay} ];then
#    blue "正在替换 [AospWifiResOverlay.apk]"
#    cp -rf ${baseAospWifiResOverlay} ${portAospWifiResOverlay}
#fi

# radio lib
# blue "信号相关"
# for radiolib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*radio*");do
#     cp -rf $radiolib build/portrom/images/system/system/lib/
# done

# for radiolib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*radio*");do
#     cp -rf $radiolib build/portrom/images/system/system/lib64/
# done


# audio lib
# blue "音频相关"
# for audiolib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*audio*");do
#     cp -rf $audiolib build/portrom/images/system/system/lib/
# done

# for audiolib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*audio*");do
#     cp -rf $audiolib build/portrom/images/system/system/lib64/
# done

# # bt lib
# blue "蓝牙相关"
# for btlib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*bluetooth*");do
#     cp -rf $btlib build/portrom/images/system/system/lib/
# done

# for btlib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*bluetooth*");do
#     cp -rf $btlib build/portrom/images/system/system/lib64/
# done


# displayconfig id
rm -rf build/portrom/images/product/etc/displayconfig/display_id*.xml
cp -rf build/baserom/images/product/etc/displayconfig/display_id*.xml build/portrom/images/product/etc/displayconfig/

blue "复制设备特性XML文件"
rm -rf build/portrom/images/product/etc/device_features/*
cp -rf devices/device_features/* build/portrom/images/product/etc/device_features/

#device_info
if [[ ${is_eu_rom} == "true" ]];then
    cp -rf build/baserom/images/product/etc/device_info.json build/portrom/images/product/etc/device_info.json
fi


yellow "添加高级重启"
rm -rf build/portrom/images/product/app/MIUISystemUIPlugin/*
cp -rf devices/MIUISystemUIPlugin.apk build/portrom/images/product/app/MIUISystemUIPlugin/

green "正在替换徕卡相机APK"
rm -rf build/portrom/images/product/priv-app/MiuiCamera
mkdir build/portrom/images/product/priv-app/MiuiCamera
cp -rf devices/MiuiCamera.apk build/portrom/images/product/priv-app/MiuiCamera/

# 修复各种疑难杂症
echo "# tosasitill here made with love" >> build/portrom/images/product/etc/build.prop
echo "ro.miui.cust_erofs=0" >> build/portrom/images/product/etc/build.prop
echo "# tosasitill here 0202 & 0227" >> build/portrom/images/system/system/build.prop
echo "ro.crypto.state=encrypted" >> build/portrom/images/system/system/build.prop
echo "debug.game.video.support=true" >> build/portrom/images/system/system/build.prop
echo "debug.game.video.speed=true" >> build/portrom/images/system/system/build.prop
sed -i "s/persist\.sys\.millet\.cgroup1/#persist\.sys\.millet\.cgroup1/" build/portrom/images/vendor/build.prop

blue "替换开机动画"
rm -rf build/portrom/images/product/media/bootanimation.zip
cp -rf devices/bootanimation.zip build/portrom/images/product/media/
# MiSound
#baseMiSound=$(find build/baserom/images/product -type d -name "MiSound")
#portMiSound=$(find build/baserom/images/product -type d -name "MiSound")
#if [ -d ${baseMiSound} ] && [ -d ${portMiSound} ];then
#    blue "正在替换 MiSound"
 #   rm -rf ./${portMiSound}/*
 #   cp -rf ./${baseMiSound}/* ${portMiSound}/
#fi

# MusicFX
#baseMusicFX=$(find build/baserom/images/product build/baserom/images/system -type d -name "MusicFX")
#portMusicFX=$(find build/baserom/images/product build/baserom/images/system -type d -name "MusicFX")
#if [ -d ${baseMusicFX} ] && [ -d ${portMusicFX} ];then
#    blue "正在替换 MusicFX"
##    rm -rf ./${portMusicFX}/*
 #   cp -rf ./${baseMusicFX}/* ${portMusicFX}/
#fi

# 人脸
baseMiuiBiometric=$(find build/baserom/images/product/app -type d -name "MiuiBiometric*")
portMiuiBiometric=$(find build/portrom/images/product/app -type d -name "MiuiBiometric*")
if [ -d "${baseMiuiBiometric}" ] && [ -d "${portMiuiBiometric}" ];then
    yellow "查找MiuiBiometric" "Searching and Replacing MiuiBiometric.."
    rm -rf ./${portMiuiBiometric}/*
    cp -rf ./${baseMiuiBiometric}/* ${portMiuiBiometric}/
else
    if [ -d "${baseMiuiBiometric}" ] && [ ! -d "${portMiuiBiometric}" ];then
        blue "未找到MiuiBiometric，替换为原包" "MiuiBiometric is missing, copying from base..."
        cp -rf ${baseMiuiBiometric} build/portrom/images/product/app/
    fi
fi

# 修复AOD问题

blue "修复.ko模块加载错误"
rm -rf build/portrom/images/vendor/lib/modules
cp -rf devices/modules build/portrom/images/vendor/lib/

# Fix boot up frame drop issue.
targetAospFrameworkResOverlay=$(find build/portrom/images/product -type f -name "AospFrameworkResOverlay.apk")



#其他机型可能没有default.prop
for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break
    fi
done

green "正在修复 NFC"

cp -rf devices/nfc/bin/hw/vendor.nxp.hardware.nfc@2.0-service build/portrom/images/vendor/bin/hw/
cp -rf devices/nfc/bin/nqnfcinfo build/portrom/images/vendor/bin/
cp -rf devices/nfc/etc/libnfc-*.conf build/portrom/images/vendor/etc/
cp -rf devices/nfc/etc/init/vendor.nxp.hardware.nfc@2.0-service.rc build/portrom/images/vendor/etc/init/
cp -rf devices/nfc/etc/sn100u_nfcon.pnscr build/portrom/images/vendor/etc/
cp -rf devices/nfc/etc/permissions/android.*.xml build/portrom/images/vendor/etc/permissions/
cp -rf devices/nfc/firmware/96_nfcCard_RTP.bin build/portrom/images/vendor/firmware/
cp -rf devices/nfc/firmware/98_nfcCardSlow_RTP.bin build/portrom/images/vendor/firmware/
cp -rf devices/nfc/lib/nfc_nci.nqx.default.hw.so build/portrom/images/vendor/lib/
cp -rf devices/nfc/lib/vendor.nxp.hardware.nfc@2.0.so build/portrom/images/vendor/lib/
cp -rf devices/nfc/lib/modules/nfc_i2c.ko build/portrom/images/vendor/lib/modules/
cp -rf devices/nfc/lib/modules/5.4-gki/nfc_i2c.ko build/portrom/images/vendor/lib/modules/5.4-gki/
cp -rf devices/nfc/lib64/nfc_nci.nqx.default.hw.so build/portrom/images/vendor/lib64/
cp -rf devices/nfc/lib64/vendor.nxp.hardware.nfc@2.0.so build/portrom/images/vendor/lib64/

green "NFC修复成功"

green "正在精简无用的 VNDK"
rm -rf build/portrom/images/system_ext/apex/com.android.vndk.v31.apex
rm -rf build/portrom/images/system_ext/apex/com.android.vndk.v32.apex
rm -rf build/portrom/images/system_ext/apex/com.android.vndk.v33.apex
green "精简完毕"

apex_file="build/portrom/images/system_ext/apex/com.android.vndk.v30.apex"
backup_apex="build/baserom/images/system_ext/apex/com.android.vndk.v30.apex"
# 检测Apex30文件是否存在
if [ -f "$apex_file" ]; then
    blue "文件 $apex_file 存在"
else
    blue "文件 $apex_file 不存在，将从备份文件拷贝"
    # 拷贝文件
    if [ -f "$backup_apex" ]; then
        cp "$backup_apex" "$apex_file"
        blue "已从备份文件拷贝到 $apex_file"
    else
        blue "备份文件 $backup_apex 也不存在，无法进行拷贝"
    fi
fi

# Fix Game Turbo error
echo "gettimeofday: 1" >> build/portrom/images/vendor/etc/seccomp_policy/qspm.policy
echo "renameat2: 1" >> build/portrom/images/vendor/etc/seccomp_policy/qspm.policy

# props from k60
echo "persist.vendor.mi_sf.optimize_for_refresh_rate.enable=1" >> build/portrom/images/vendor/build.prop
echo "ro.vendor.mi_sf.ultimate.perf.support=true"  >> build/portrom/images/vendor/build.prop

# https://source.android.com/docs/core/graphics/multiple-refresh-rate
echo "ro.surface_flinger.use_content_detection_for_refresh_rate=false" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_touch_timer_ms=0" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_idle_timer_ms=0" >> build/portrom/images/vendor/build.prop

#解决开机报错问题
targetVintf=$(find build/portrom/images/system_ext/etc/vintf -type f -name "manifest.xml")
if [ -f "$targetVintf" ]; then
    # Check if the file contains $vndk_version
    if grep -q "<version>$vndk_version</version>" "$targetVintf"; then
        yellow "${vndk_version}已存在，跳过修改" "The file already contains the version $vndk_version. Skipping modification."
    else
        # If it doesn't contain $vndk_version, then add it
        ndk_version="<vendor-ndk>\n     <version>$vndk_version</version>\n </vendor-ndk>"
        sed -i "/<\/vendor-ndk>/a$ndk_version" "$targetVintf"
        yellow "添加成功" "Version $vndk_version added to $targetVintf"
    fi
else
    blue "File $targetVintf not found."
fi



#blue "解除状态栏通知个数限制(默认最大6个)" "Set SystemUI maxStaticIcons to 6 by default."
#patch_smali "MiuiSystemUI.apk" "NotificationIconAreaController.smali" "iput p10, p0, Lcom\/android\/systemui\/statusbar\/phone\/NotificationIconContainer;->mMaxStaticIcons:I" "const\/4 p10, 0x6\n\n\tiput p10, p0, Lcom\/android\/systemui\/statusbar\/phone\/NotificationIconContainer;->mMaxStaticIcons:I"

if [[ ${is_eu_rom} == "true" ]];then
    patch_smali "miui-services.jar" "SystemServerImpl.smali" ".method public constructor <init>()V/,/.end method" ".method public constructor <init>()V\n\t.registers 1\n\tinvoke-direct {p0}, Lcom\/android\/server\/SystemServerStub;-><init>()V\n\n\treturn-void\n.end method" "regex"

else
    if [[ "$compatible_matrix_matches_enabled" == "false" ]]; then
        patch_smali "framework.jar" "Build.smali" ".method public static isBuildConsistent()Z" ".method public static isBuildConsistent()Z \n\n\t.registers 1 \n\n\tconst\/4 v0,0x1\n\n\treturn v0\n.end method\n\n.method public static isBuildConsistent_bak()Z"
    fi
    if [[ ! -d tmp ]];then
        mkdir -p tmp/
    fi
    blue "开始移除 Android 签名校验" "Disalbe Android 14 Apk Signature Verfier"
    mkdir -p tmp/services/
    cp -rf build/portrom/images/system/system/framework/services.jar tmp/services/services.jar

    7z x -y tmp/services/services.jar *.dex -otmp/services > /dev/null 2>&1
    target_method='getMinimumSignatureSchemeVersionForTargetSdk'
    for dexfile in tmp/services/*.dex;do
        smali_fname=${dexfile%.*}
        smali_base_folder=$(echo $smali_fname | cut -d "/" -f 3)
        java -jar bin/apktool/baksmali.jar d --api ${port_android_sdk} ${dexfile} -o tmp/services/$smali_base_folder
    done

    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(echo "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } &&    blue "${smali_file}  修改成功"
        old_smali_dir=$smali_dir
    done < <(find tmp/services -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)

    for smali_dir in "${smali_dirs[@]}"; do
        blue "反编译成功，开始回编译 $smali_dir"
        java -jar bin/apktool/smali.jar a --api ${port_android_sdk} tmp/services/${smali_dir} -o tmp/services/${smali_dir}.dex
        pushd tmp/services/ > /dev/null 2>&1
        7z a -y -mx0 -tzip services.jar ${smali_dir}.dex > /dev/null 2>&1
        popd > /dev/null 2>&1
    done

    cp -rf tmp/services/services.jar build/portrom/images/system/system/framework/services.jar

fi

# 主题防恢复
if [ -f build/portrom/images/system/system/etc/init/hw/init.rc ];then
	sed -i '/on boot/a\'$'\n''    chmod 0731 \/data\/system\/theme' build/portrom/images/system/system/etc/init/hw/init.rc
fi


mkdir -p tmp/app
kept_data_apps=("Weather" "DeskClock" "Gallery" "SoundRecorder" "ScreenRecorder" "Calculator" "CleanMaster" "Calendar" "Compass" "Notes" "AI" "Ai" "ocr" "OCR" "Ocr" "ai")
for app in "${kept_data_apps[@]}"; do
    mv build/portrom/images/product/data-app/*"${app}"* tmp/app/ >/dev/null 2>&1
done

rm -rf build/portrom/images/product/data-app/*
cp -rf tmp/app/* build/portrom/images/product/data-app
rm -rf tmp/app
rm -rf build/portrom/images/product/priv-app/MIUIMusicT
rm -rf build/portrom/images/product/priv-app/MIUIVideo
rm -rf build/portrom/images/product/app/MiGameService_8450
rm -rf build/portrom/images/product/app/HybridPlatform
rm -rf build/portrom/images/product/app/system
rm -rf build/portrom/images/product/app/Updater
rm -rf build/portrom/images/product/priv-app/MIUIBrowser
rm -rf build/portrom/images/system/verity_key
rm -rf build/portrom/images/vendor/verity_key
rm -rf build/portrom/images/product/verity_key
rm -rf build/portrom/images/system/recovery-from-boot.p
rm -rf build/portrom/images/vendor/recovery-from-boot.p
rm -rf build/portrom/images/product/recovery-from-boot.p
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/com.google.android.apps.nbu*
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/dynamic/com.google.android.apps.nbu*
# build.prop 修改
blue "正在修改 build.prop" "Modifying build.prop"
#
#change the locale to English
export LC_ALL=en_US.UTF-8
buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}" "modifying ${i}"
    sed -i "s/ro.build.date=.*/ro.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.build.date.utc=.*/ro.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.odm.build.date=.*/ro.odm.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.odm.build.date.utc=.*/ro.odm.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.vendor.build.date=.*/ro.vendor.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system.build.date=.*/ro.system.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system.build.date.utc=.*/ro.system.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.product.build.date=.*/ro.product.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.product.build.date.utc=.*/ro.product.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system_ext.build.date=.*/ro.system_ext.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc=${buildUtc}/g" ${i}

    sed -i "s/ro.product.device=.*/ro.product.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.product.name=.*/ro.product.product.name=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.odm.device=.*/ro.product.odm.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.vendor.device=.*/ro.product.vendor.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system.device=.*/ro.product.system.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.board=.*/ro.product.board=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system_ext.device=.*/ro.product.system_ext.device=${base_rom_code}/g" ${i}
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    #全局替换device_code
    if [[ $port_mios_version_incremental != *DEV* ]];then
        sed -i "s/$port_device_code/$base_device_code/g" ${i}
    fi
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    if [[ ${is_eu_rom} == "true" ]];then
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}_xiaomieu_global/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=xiaomi.eu/g" ${i}

    else
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=${build_host}/g" ${i}
    fi
    sed -i "s/ro.build.characteristics=tablet/ro.build.characteristics=nosdcard/g" ${i}
    sed -i "s/ro.config.miui_multi_window_switch_enable=true/ro.config.miui_multi_window_switch_enable=false/g" ${i}
    sed -i "s/ro.config.miui_desktop_mode_enabled=true/ro.config.miui_desktop_mode_enabled=false/g" ${i}
    sed -i "/ro.miui.density.primaryscale=.*/d" ${i}
    sed -i "/persist.wm.extensions.enabled=true/d" ${i}
done

#sed -i -e '$a\'$'\n''persist.adb.notify=0' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.usb.config=mtp,adb' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.disable_rescue=true' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.miui.extm.enable=0' build/portrom/images/system/system/build.prop

# 屏幕密度修修改
for prop in $(find build/baserom/images/product build/baserom/images/system -type f -name "build.prop");do
    base_rom_density=$(< "$prop" grep "ro.sf.lcd_density" |awk 'NR==1' |cut -d '=' -f 2)
    if [ "${base_rom_density}" != "" ];then
        green "底包屏幕密度值 ${base_rom_density}" "Screen density: ${base_rom_density}"
        break
    fi
done

# 未在底包找到则默认440,如果是其他值可自己修改
[ -z ${base_rom_density} ] && base_rom_density=440

found=0
for prop in $(find build/portrom/images/product build/portrom/images/system -type f -name "build.prop");do
    if grep -q "ro.sf.lcd_density" ${prop};then
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" ${prop}
        found=1
    fi
    sed -i "s/persist.miui.density_v2=.*/persist.miui.density_v2=${base_rom_density}/g" ${prop}
done

if [ $found -eq 0  ]; then
        blue "未找到ro.fs.lcd_density，build.prop新建一个值$base_rom_density" "ro.fs.lcd_density not found, create a new value ${base_rom_density} "
        echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/product/etc/build.prop
fi

echo "ro.miui.cust_erofs=0" >> build/portrom/images/product/etc/build.prop

#vendorprop=$(find build/portrom/images/vendor -type f -name "build.prop")
#odmprop=$(find build/baserom/images/odm -type f -name "build.prop" |awk 'NR==1')
#if [ "$(< $vendorprop grep "sys.haptic" |awk 'NR==1')" != "" ];then
#    blue "复制 haptic prop 到 odm"
#    < $vendorprop grep "sys.haptic" >>${odmprop}
#fi

#Fix： mi10 boot stuck at the first screen
sed -i "s/persist\.sys\.millet\.cgroup1/#persist\.sys\.millet\.cgroup1/" build/portrom/images/vendor/build.prop


# Millet fix
blue "修复Millet" "Fix Millet"

millet_netlink_version=$(grep "ro.millet.netlink" build/baserom/images/product/etc/build.prop | cut -d "=" -f 2)

if [[ -n "$millet_netlink_version" ]]; then
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
else
  blue "原包未发现ro.millet.netlink值，请手动赋值修改(默认为29)" "ro.millet.netlink property value not found, change it manually(29 by default)."
  millet_netlink_version=29
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
fi
# add advanced texture
if ! is_property_exists persist.sys.background_blur_supported build/portrom/images/product/etc/build.prop; then
    echo "persist.sys.background_blur_supported=true" >> build/portrom/images/product/etc/build.prop
    echo "persist.sys.background_blur_version=2" >> build/portrom/images/product/etc/build.prop
else
    sed -i "s/persist.sys.background_blur_supported=.*/persist.sys.background_blur_supported=true/" build/portrom/images/product/etc/build.prop
fi


unlock_device_feature "Whether support AI Display"  "bool" "support_AI_display"
unlock_device_feature "device support screen enhance engine"  "bool" "support_screen_enhance_engine"
unlock_device_feature "Whether suppot Android Flashlight Controller"  "bool" "support_android_flashlight"
unlock_device_feature "Whether support SR for image display"  "bool" "support_SR_for_image_display"

# Unlock MEMC; unlocking the screen enhance engine is a prerequisite.
# This feature add additional frames to videos to make content appear smooth and transitions lively.
if  grep -q "ro.vendor.media.video.frc.support" build/portrom/images/vendor/build.prop ;then
    sed -i "s/ro.vendor.media.video.frc.support=.*/ro.vendor.media.video.frc.support=true/" build/portrom/images/vendor/build.prop
else
    echo "ro.vendor.media.video.frc.support=true" >> build/portrom/images/vendor/build.prop
fi
# Game splashscreen speed up
echo "debug.game.video.speed=true" >> build/portrom/images/product/etc/build.prop
echo "debug.game.video.support=true" >> build/portrom/images/product/etc/build.prop



if [[ ${is_eu_rom} == true ]];then
    patch_smali "MiSettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"

else
    patch_smali "MISettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"
fi

# Unlock eyecare mode
unlock_device_feature "default rhythmic eyecare mode" "integer" "default_eyecare_mode" "2"
unlock_device_feature "default texture for paper eyecare" "integer" "paper_eyecare_default_texture" "0"


if [[ ${port_rom_code} == "munch_cn" ]];then
    # Add missing camera permission android.permission.TURN_SCREEN_ON
    # this missing permission will cause device stuck on boot with higher custom Camera(eg: 5.2.0.XX) integrated
    sed -i 's|<permission name="android.permission.SYSTEM_CAMERA" />|<permission name="android.permission.SYSTEM_CAMERA" />\n\t\t<permission name="android.permission.TURN_SCREEN_ON" />|' build/portrom/images/product/etc/permissions/privapp-permissions-product.xml

fi

# Unlock Celluar Sharing feature
targetMiuiFrameworkResOverlay=$(find build/portrom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
if [[ -f $targetMiuiFrameworkResOverlay ]]; then
    mkdir tmp/  > /dev/null 2>&1
    targetFrameworkExtRes=$(find build/portrom/images/system_ext -type f -name "framework-ext-res.apk")
    bin/apktool/apktool d $targetFrameworkExtRes -o tmp/framework-ext-res -f > /dev/null 2>&1
    if grep -r config_celluar_shared_support tmp/framework-ext-res/ ; then
        filename=$(basename $targetMiuiFrameworkResOverlay)
        yellow "开启通信共享功能" "Enable Celluar Sharing feature"
        targetDir=$(echo "$filename" | sed 's/\..*$//')
        bin/apktool/apktool d $targetMiuiFrameworkResOverlay -o tmp/$targetDir -f > /dev/null 2>&1
        bool_xml=$(find tmp/$targetDir -type f -name "bools.xml")
        if ! xmlstarlet sel -t -c "//bool[@name='config_celluar_shared_support']" "$bool_xml" | grep -q '<bool'; then
            blue "bools.xml: 布尔值config_celluar_shared_support未找到，正在添加..." "bools.xml: Boolean value config_celluar_shared_support not found, adding it..."
            xmlstarlet ed -L -s /resources -t elem -n bool -v "true" \
            -i "//bool[not(@name)]" -t attr -n name -v "config_celluar_shared_support" $bool_xml
        fi
        public_xml=$(find tmp/$targetDir -type f -name "public.xml")

        LAST_ID=$(xmlstarlet sel -t -m "//public[@type='bool'][last()]" -v "@id" "$public_xml")

        if [ -z "$LAST_ID" ]; then
            blue "在 public.xml 中未找到布尔值，分配config_celluar_shared_support默认 ID: 0x7f020000" "Boolean value not found in public.xml, assigning default ID: 0x7f020000"
            NEW_ID_HEX="0x7f020000"
        else
            blue "public.xml: 找到最后一个布尔值 ID: $LAST_ID" "public.xml: Last boolean value ID $LAST_ID found"
            LAST_ID_DEC=$((LAST_ID))
            NEW_ID_DEC=$((LAST_ID_DEC + 1))
            NEW_ID_HEX=$(printf "0x%08x" "$NEW_ID_DEC")
            blue "public.xml: 分配config_celluar_shared_support新ID: $NEW_ID_HEX" "public.xml: Assigning new ID: $NEW_ID_HEX to config_celluar_shared_support"
        fi
        xmlstarlet ed -L -s /resources -t elem -n public -v "" \
            -i "//public[not(@type)]" -t attr -n type -v "bool" \
            -i "//public[not(@name)]" -t attr -n name -v "config_celluar_shared_support" \
            -i "//public[not(@id)]" -t attr -n id -v "$NEW_ID_HEX" "$public_xml"

        bin/apktool/apktool b tmp/$targetDir -o tmp/$filename > /dev/null 2>&1 || error "apktool 打包失败" "apktool mod failed"
        cp -rf tmp/$filename $targetMiuiFrameworkResOverlay
        rm -rf tmp
    fi
fi


#Add perfect icons
blue "Integrating perfect icons"
git clone --depth=1 https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons &>/dev/null
for pkg in "$work_dir"/build/portrom/images/product/media/theme/miui_mod_icons/dynamic/*; do
  if [[ -d "$work_dir"/icons/icons/$pkg ]]; then
    rm -rf "$work_dir"/icons/icons/$pkg
  fi
done
rm -rf "$work_dir"/icons/icons/com.xiaomi.scanner
mv "$work_dir"/build/portrom/images/product/media/theme/default/icons "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip
rm -rf "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
mkdir -p "$work_dir"/icons/res
mv "$work_dir"/icons/icons "$work_dir"/icons/res/drawable-xxhdpi
cd "$work_dir"/icons
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip res
cd "$work_dir"/icons/themes/Hyper/
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd "$work_dir"/icons/themes/common/
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip "$work_dir"/build/portrom/images/product/media/theme/default/icons
mv "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
rm -rf "$work_dir"/icons
cd "$work_dir"

# Optimize prop from K40s
if ! is_property_exists ro.miui.surfaceflinger_affinity build/portrom/images/product/etc/build.prop; then
    echo "ro.miui.surfaceflinger_affinity=true" >> build/portrom/images/product/etc/build.prop
fi

# 去除avb校验
blue "去除avb校验" "Disable avb verification."
for fstab in $(find build/portrom/images/ -type f -name "fstab.*");do
    blue "Target: $fstab"
    sed -i "s/,avb_keys=.*avbpubkey//g" $fstab
    sed -i "s/,avb=vbmeta_system//g" $fstab
    sed -i "s/,avb=vbmeta_vendor//g" $fstab
    sed -i "s/,avb=vbmeta//g" $fstab
    sed -i "s/,avb//g" $fstab
done

# data 加密
remove_data_encrypt=$(grep "remove_data_encryption" bin/port_config |cut -d '=' -f 2)
if [ ${remove_data_encrypt} = "true" ];then
    blue "去除data加密"
    for fstab in $(find build/portrom/images -type f -name "fstab.*");do
		blue "Target: $fstab"
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts//g" $fstab
        sed -i "s/,fileencryption=ice//g" $fstab
		sed -i "s/fileencryption/encryptable/g" $fstab
	done
fi

green "添加面具"
mkdir build/portrom/images/product/data-app/Kitsune
cp -rf devices/app-release.apk build/portrom/images/product/data-app/Kitsune/
mv build/portrom/images/product/data-app/Kitsune/app-release.apk build/portrom/images/product/data-app/Kitsune/Kitsune.apk
green "添加 Via"
mkdir build/portrom/images/product/data-app/via
cp -rf devices/via.apk build/portrom/images/product/data-app/via/

for pname in ${port_partition};do
    rm -rf build/portrom/images/${pname}.img
done
echo "${pack_type}">fstype.txt
superSize="9126805504"
green "Super大小为${superSize}" "Super image size: ${superSize}"
green "开始打包镜像" "Packing super.img"
for pname in ${super_list};do
    if [ -d "build/portrom/images/$pname" ];then
        if [[ "$OSTYPE" == "darwin"* ]];then
            thisSize=$(find build/portrom/images/${pname} | xargs stat -f%z | awk ' {s+=$1} END { print s }' )
        else
            thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        fi
        case $pname in
            mi_ext) addSize=4194304 ;;
            odm) addSize=4217728 ;;
            system|vendor|system_ext) addSize=80217728 ;;
            product) addSize=100217728 ;;
            *) addSize=8554432 ;;
        esac
        if [ "$pack_type" = "EXT" ];then
            for fstab in $(find build/portrom/images/${pname}/ -type f -name "fstab.*");do
                #sed -i '/overlay/d' $fstab
                sed -i '/system * erofs/d' $fstab
                sed -i '/system_ext * erofs/d' $fstab
                sed -i '/vendor * erofs/d' $fstab
                sed -i '/product * erofs/d' $fstab
            done
            thisSize=$(echo "$thisSize + $addSize" |bc)
            blue 以[$pack_type]文件系统打包[${pname}.img]大小[$thisSize] "Packing [${pname}.img]:[$pack_type] with size [$thisSize]"
            python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config
            python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts
            make_ext4fs -J -T $(date +%s) -S build/portrom/images/config/${pname}_file_contexts -l $thisSize -C build/portrom/images/config/${pname}_fs_config -L ${pname} -a ${pname} build/portrom/images/${pname}.img build/portrom/images/${pname}

            if [ -f "build/portrom/images/${pname}.img" ];then
                green "成功以大小 [$thisSize] 打包 [${pname}.img] [${pack_type}] 文件系统" "Packing [${pname}.img] with [${pack_type}], size: [$thisSize] success"
                #rm -rf build/baserom/images/${pname}
            else
                error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Packing [${pname}] with[${pack_type}] filesystem failed!"
            fi
        else

                blue 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
                python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config
                python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts
                #sudo perl -pi -e 's/\\@/@/g' build/portrom/images/config/${pname}_file_contexts
                mkfs.erofs --mount-point ${pname} --fs-config-file build/portrom/images/config/${pname}_fs_config --file-contexts build/portrom/images/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}
                if [ -f "build/portrom/images/${pname}.img" ];then
                    green "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
                    #rm -rf build/portrom/images/${pname}
                else
                    error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
                    exit 1
                fi
        fi
        unset fsType
        unset thisSize
    fi
done
rm fstype.txt

# 打包 super.img

if [[ "$is_ab_device" == false ]];then
    blue "打包A-only super.img" "Packing super.img for A-only device"
    lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor;do
        if [ -f "build/portrom/images/${pname}.img" ];then
            if [[ "$OSTYPE" == "darwin"* ]];then
               subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
            else
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            fi
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
else
    blue "打包V-A/B机型 super.img" "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

    for pname in ${super_list};do
        if [ -f "build/portrom/images/${pname}.img" ];then
            subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=build/portrom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
fi
lpmake $lpargs
#echo "lpmake $lpargs"
if [ -f "build/portrom/images/super.img" ];then
    green "成功打包 super.img" "Pakcing super.img done."
else
    error "无法打包 super.img"  "Unable to pack super.img."
    exit 1
fi
for pname in ${super_list};do
    rm -rf build/portrom/images/${pname}.img
done

os_type="HyperOS"
if [[ ${is_eu_rom} == true ]];then
    os_type="xiaomi.eu"
fi

blue "正在压缩 super.img" "Comprising super.img"
zstd --rm build/portrom/images/super.img -o build/portrom/images/super.zst
mkdir -p out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/
mkdir -p out/${os_type}_${device_code}_${port_rom_version}/bin/windows/

blue "正在生成刷机脚本" "Generating flashing script"
if [[ "$is_ab_device" == false ]];then
    busybox unix2dos out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    sed -i "s/portversion/${port_rom_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary

else
    mkdir -p out/${os_type}_${device_code}_${port_rom_version}/images/
    mv -f build/portrom/images/super.zst out/${os_type}_${device_code}_${port_rom_version}/images/
    cp -rf devices/haydn/* out/${os_type}_${device_code}_${port_rom_version}/
fi

find out/${os_type}_${device_code}_${port_rom_version} |xargs touch
pushd out/${os_type}_${device_code}_${port_rom_version}/  || exit
zip -r ${os_type}_${device_code}_${port_rom_version}.zip ./*
mv ${os_type}_${device_code}_${port_rom_version}.zip ../
popd || exit
pack_timestamp=$(date +"%m%d%H%M")
hash=$(md5sum out/${os_type}_${device_code}_${port_rom_version}.zip |head -c 10)
if [[ $pack_type == "EROFS" ]];then
    pack_type="ROOT_"${pack_type}
    yellow "检测到打包类型为EROFS,请确保官方内核支持，或者在devices机型目录添加有支持EROFS的内核，否者将无法开机！" "EROFS filesystem detected. Ensure compatibility with the official boot.img or ensure a supported boot_tv.img is placed in the device folder."
fi
mv out/${os_type}_${device_code}_${port_rom_version}.zip out/${os_type}_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip
green "移植完毕" "Porting completed"
green "输出包路径：" "Output: "
green "$(pwd)/out/${os_type}_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip"
