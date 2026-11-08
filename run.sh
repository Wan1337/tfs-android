#!/system/bin/sh
# MT 管理器扩展包入口：把所有参数透传给 /data/local/tmp/tfs/tfs.sh
exec su -c "sh /data/local/tmp/tfs/tfs.sh $*"
