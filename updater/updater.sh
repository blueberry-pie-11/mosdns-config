#!/bin/bash

# 设置默认变量
# LOG_FILE="./updater.log"
# RULES_DIR="rules"
# DOWNLOAD_DIR="download"
# MOSDNS_GEO_SET_DIR="/docker/mosdns/data/geo_set"
# GEOIP_TAGS_URL="./tags/geoip_tags.txt"
# GEOSITE_TAGS_URL="./tags/geosite_tags.txt"
# GEOIP_NAME="geoip.dat"
# GEOSITE_NAME="geosite.dat"
# GEOIP_SHA_NAME="geoip.dat.sha256sum"
# GEOSITE_SHA_NAME="geosite.dat.sha256sum"
# GEOIP_SHA_DL_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum"
# GEOSITE_SHA_DL_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum"
# GEOIP_DL_URL=https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
# GEOSITE_DL_URL=https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

# Initialize variables from config.yml file
# Read variables from config.yml and set default values
init() {
    local config_file="$1"
    # 从config.yml中读取变量，并设置默认值
    while IFS= read -r line; do
        # 排除\r 和 \n
        if [[ $line != $'\n' ]] && [[ $line != $'\r' ]]; then
            # 替换": "为"#",方便进行字符串分割，防止出现http链接被错误分割
            line=$(echo "$line" | sed 's/\r$//' | sed 's/:\s*/#/')
            # 将$line使用 "#" 分割成key、value，并去除value首位可能存在的引号以及空格
            key=$(echo "$line" | cut -d '#' -f 1 | tr '[:lower:]' '[:upper:]')
            value=$(echo "$line" | cut -d '#' -f 2 | sed 's/^\s*"\s*//' | sed 's/\s*"\s*$//')
            # 声明全局变量
            declare -g "$key=$value"
        fi
    done <"$config_file"
}

# 从config.json文件中读取json格式的变量

# create rules directory
#
# This function is used to create the rules directory and the download directory.
# It also creates the updater.log file if necessary and sets the execute permission of v2dat.
function create_dir() {
    # Check if the updater.log file size exceeds 10kB and delete it if necessary
    if [ $(stat -c%s "$LOG_FILE") -gt 102400 ]; then
        rm $LOG_FILE -rf
        echo "Deleting the old $LOG_FILE file..." >>"$LOG_FILE"

    fi

    # create rules directory
    mkdir -p $RULES_DIR $DOWNLOAD_DIR >>"$LOG_FILE"
    chmod +x ./v2dat >>"$LOG_FILE"
}

# Read geoip and geosite tags from the corresponding files.
#
# This function reads the geoip and geosite tags from the files geoip_tags.txt and
# geosite_tags.txt respectively. The function stores the tags in the arrays GEOIP_TAGS
# and GEOSITE_TAGS respectively.
#
# The function also prints the tags to the log file.
function get_tags() {
    echo "[INFO] Reading geoip tags from $GEOIP_TAGS_URL..." >>"$LOG_FILE"
    while IFS= read -r line; do
        # 排除\r 和 \n
        if [[ $line != $'\n' ]] && [[ $line != $'\r' ]]; then
            line=$(echo "$line" | sed 's/\r$//')
            GEOIP_TAGS+=("$line")
        fi
    done <"$GEOIP_TAGS_URL"

    echo "[INFO] Reading geosite tags from $GEOSITE_TAGS_URL..." >>"$LOG_FILE"
    while IFS= read -r line; do
        if [[ $line != $'\n' ]] && [[ $line != $'\r' ]]; then
            line=$(echo "$line" | sed 's/\r$//')
            GEOSITE_TAGS+=("$line")
        fi
    done <"$GEOSITE_TAGS_URL"

    echo "[NOTICE] GEOIP_TAGS: ${GEOIP_TAGS[@]}" >>"$LOG_FILE"
    echo "[NOTICE] GEOSITE_TAGS: ${GEOSITE_TAGS[@]}" >>"$LOG_FILE"
}

# check sha256 of geoip/geosite data, if the sha256 is not matched,
# download the new data file, and update the local data file and sha256 file
#
# @param geo_category: geoip or geosite
# @param geo_sha_dl_url: url to download sha256 file
#
# @return: 0 for not up to date, 1 for up to date
function check_update() {
    # geo category, such as geoip or geosite
    local geo_category="$1"
    # sha256 file name, such as geoip.dat.sha256
    local geo_sha="$1.dat.sha256sum"
    # data file name, such as geoip.dat
    local geo="$1.dat"
    # url to download sha256 file
    local geo_sha_dl_url="$2"

    echo "[NOTICE] check $geo_category sha256" >>"$LOG_FILE"

    # download sha256 file from url
    wget --timeout=30 --waitretry=5 --tries=3 -q "$geo_sha_dl_url" -O "$DOWNLOAD_DIR/$geo_sha"

    # if download sha256 file successfully
    if [ $? == 0 ]; then

        echo "[NOTICE] get $geo_category sha256 successfully!" >>"$LOG_FILE"

        # if both sha256 file and data file exist
        if [ -f "$DOWNLOAD_DIR/$geo" ]; then

            # if the downloaded sha256 is matched with the local sha256
            if [ "$(sha256sum $DOWNLOAD_DIR/$geo | awk '{print $1}')" == "$(grep "$geo" $DOWNLOAD_DIR/$geo_sha | awk '{print $1}')" ]; then
                echo "[NOTICE] $geo_category is not up to date!" >>"$LOG_FILE"
                # return not up to date
                return 0
            else
                echo "[NOTICE] $geo_category is up to date!" >>"$LOG_FILE"
                # return up to date
                return 1
            fi
        else
            echo "[NOTICE] $geo_category data file does not exist!" >>"$LOG_FILE"
            echo "[NOTICE] $geo_category is up to date!" >>"$LOG_FILE"
            # return up to date
            return 1
        fi
    else
        echo "[WARNING] get $geo_category sha256 failed!" >>"$LOG_FILE"
        # return up to date
        return 1
    fi
}

# download geodata, return 0 if download successfully, otherwise return 1
#
# @param geo_category the geo category, such as geoip or geosite
# @param geo_dl_url url to download data file
#
# @return 0 if download successfully, otherwise return 1
function download_geodata() {
    # geo category, such as geoip or geosite
    local geo_category="$1"

    # geo data file name, such as geoip.dat
    local geo="$1.dat"

    # url to download geo data file
    local geo_dl_url="$2"

    # log download start
    echo "[NOTICE] download $geo_category" >>"$LOG_FILE"

    # download geodata
    wget --timeout=30 --waitretry=5 --tries=3 -q --show-progress "$geo_dl_url" -O "$DOWNLOAD_DIR/$geo"

    # if download successfully
    if [ $? == 0 ]; then
        echo "[NOTICE] get $geo_category successfully!" >>"$LOG_FILE"

        # return 0
        return 0
    else
        # log download failed
        echo "[WARNING] get $geo_category failed! please check your network!" >>"$LOG_FILE"

        # return 1
        return 1
    fi
}

# unpack downloaded geodata to rules directory
#
# @param geo_category the geo category, such as geoip or geosite
function unpack_geodata() {
    # geo category, such as geoip or geosite
    local geo_category="$1"

    # geo data file name, such as geoip.dat
    local geo="$1.dat"

    # geo data file tags, such as geosite_tags or geoip_tags
    local geo_tags=()
    if [ "$geo_category" == "geosite" ]; then
        geo_tags=("${GEOSITE_TAGS[@]}")
    else
        geo_tags=("${GEOIP_TAGS[@]}")
    fi

    # log unpack start
    echo "[NOTICE] unpack $geo_category" >>"$LOG_FILE"

    # unpack each tag
    for tag in "${geo_tags[@]}"; do
        # unpack geodata
        ./v2dat unpack "$geo_category" -o "$RULES_DIR" -f "$tag" "$DOWNLOAD_DIR/$geo"
    done
}

#
#
# starting updater...
#
#
# 初始化，从config.yml中读取变量，并设置全局变量
init "./config.yml"
# echo "Log File: $LOG_FILE"
# echo "GEOIP_SHA_DL_URL: $GEOIP_SHA_DL_URL"
echo "===============================================" >>"$LOG_FILE"
echo "$(date +'%Y-%m-%d %H:%M:%S'): starting updater..." >>"$LOG_FILE"
# create rules and download directory
create_dir
# 从文件geoip_tags.txt中读取数组GEOIP_TAGS，从geosite_tags.txt中读取数组GEOSITE_TAGS
GEOIP_TAGS=()
GEOSITE_TAGS=()
get_tags
# echo "GEOIP_TAGS: ${GEOIP_TAGS[@]}"
# echo "GEOSITE_TAGS: ${GEOSITE_TAGS[@]}"
#
#
# 调用函数更新geoip.dat和geosite.dat
#
# 初始化check_update返回值
geoip_need_update=0
geosite_need_update=0
#
# 更新geoip
check_update "geoip" "$GEOIP_SHA_DL_URL"
geoip_need_update=$?
# echo "geoip_need_update: $geoip_need_update"
if [ $geoip_need_update == 1 ]; then
    echo "[NOTICE] geoip need update, download geoip data file" >>"$LOG_FILE"
    download_geodata "geoip" "$GEOIP_DL_URL"
else
    echo "[NOTICE] geoip don't need update" >>"$LOG_FILE"
fi
# 删除旧导出文件
rm $RULES_DIR/geoip*.txt -rf
# 每次都导出txt文件，防止出现添加tags而geodata不需要更新，导致导出的txt文件不完整
unpack_geodata "geoip"

# 更新geosite
check_update "geosite" "$GEOSITE_SHA_DL_URL"
geosite_need_update=$?
if [ $geosite_need_update == 1 ]; then
    echo "[NOTICE] geosite need update, download geosite data file" >>"$LOG_FILE"
    download_geodata "geosite" "$GEOSITE_DL_URL"
else
    echo "[NOTICE] geosite don't need update" >>"$LOG_FILE"
fi
# 删除旧导出文件
rm $RULES_DIR/geosite*.txt -rf
unpack_geodata "geosite"

# 第三方mosdns调用
# geoip or geosite 导出文件需要更新
# 覆盖目录geo_set下geo文件
echo "[NOTICE] copy geo files to geo_set" >>$LOG_FILE
cp $RULES_DIR/*.txt $MOSDNS_GEO_SET_DIR/ -Rf

# 重启mosdns
echo "[NOTICE] restart mosdns..." >>$LOG_FILE
docker restart mosdns

# if [ $geoip_need_update == 1 ] || [ $geosite_need_update == 1 ]; then
#     # geoip or geosite 导出文件需要更新
#     # 覆盖目录geo_set下geo文件
#     echo "[NOTICE] copy geo files to geo_set" >>$LOG_FILE
#     for tag in "${GEOIP_TAGS[@]}"; do
#         cp $RULES_DIR/geoip_$tag.txt $MOSDNS_GEO_SET_DIR/ -Rf
#     done
#     for tag in "${GEOSITE_TAGS[@]}"; do
#         cp $RULES_DIR/geosite_$tag.txt $MOSDNS_GEO_SET_DIR/ -Rf
#     done

#     # 重启mosdns
#     echo "[NOTICE] restart mosdns..." >>$LOG_FILE
#     docker restart mosdns
# else
#     echo "[NOTICE] mosdns's geo files not need update" >>$LOG_FILE
# fi

echo "$(date +'%Y-%m-%d %H:%M:%S'): updater finished!" >>$LOG_FILE
echo "===============================================" >>$LOG_FILE
echo "" >>$LOG_FILE
echo "" >>$LOG_FILE
echo "" >>$LOG_FILE
