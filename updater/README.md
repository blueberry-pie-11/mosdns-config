# geodata_updater

自动下载 geoip 和 geosite，并根据 tag 导出文本文件，用于 mosdns 使用

### 1.安装 curl、bash、jq 以及 wget

### 2.tags.txt 文件中最后一行必须回车，使光标进入下一行

### 3.设置 crontab -e

```
    0 */12 * * *  cd /docker/mosdns/data/updater/ && bash updater.sh
```

### 4.重启crond

```
    rc-service crond restart
```
