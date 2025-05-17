# /opt目录磁盘空间不足，新增一块80G盘扩容

# 确认/opt是否做LVM，如果已做LVM可在线扩容，如果没有则需使用切换挂载的方式
# 如果能看到/opt挂载在/dev/mapper/xxx或/dev/ubuntu-vg/xxx之类的设备，通常就是做了LVM

df -Th /opt
lsblk
mount | grep /opt

# /opt未做LVM

# 使用如下方法扩容磁盘
1、备份原数据
cp -a /opt /opt.bak

2、分区并格式化新磁盘
fdisk /dev/sdb
mkfs.ext4 /dev/sdb1
# 依次输入：
n
p
# 选择扇区和大小都默认即可，最后输入w保存退出

3、临时挂载新分区并迁移数据
mount /dev/sdb1 /mnt
rsync -avx /opt/ /mnt/

4、切换挂载
umount /opt
# 如果显示mv: cannot move '/opt' to '/opt.old': Device or resource busy
# 使用lsof | grep /opt 或fuser -vm /opt 查找占用进程，确认进程可杀死后再卸载
mv /opt /opt.old
mkdir -pv /opt
umount /mnt
mount /dev/sdb1 /opt

5、设置自动挂载
# 由于/opt是在部署系统时就已分区的，因此要先将原来的/etc/fstab中/opt的挂载点注释掉，否则重启后还是会默认挂载之前的分区
echo '/dev/sdb1 /opt ext4 defaults 0 2' | sudo tee -a /etc/fstab

6、确认新增磁盘成功且/opt使用正常后删除旧数据和备份数据
rm -rf /opt.old
rm -rf /opt.bak