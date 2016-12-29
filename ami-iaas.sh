mv /etc/yum.repos.d/* ~/

# Create the filesystems 
parted /dev/xvdf --script 'mklabel msdos mkpart primary 1M 512M mkpart primary 512M -1s print quit'
mkfs.xfs -L BOOTFS -f /dev/xvdf1
pvcreate /dev/xvdf2
vgcreate -s 4 vg1 /dev/xvdf2
# Create the volumes 
lvcreate -n tmp -L 1G vg1
lvcreate -n home -L 1G vg1
lvcreate -n var -L 7G vg1
lvcreate -n var_log -L 1G vg1
lvcreate -n var_log_audit -L 512M vg1
lvcreate -n swap -L 2G vg1
lvcreate -n root -l 100%FREE vg1
# Create the file systems 
mkfs.xfs /dev/vg1/home
mkfs.xfs /dev/vg1/var_log
mkfs.xfs /dev/vg1/var_log_audit
mkfs.xfs /dev/vg1/tmp
mkfs.xfs /dev/vg1/var
mkfs.xfs /dev/vg1/root
mkswap /dev/vg1/swap

# mount file systems
mkdir -p /mnt/ec2-image
mount /dev/mapper/vg1-root /mnt/ec2-image
mkdir -p /mnt/ec2-image/{tmp,home,var,boot}
mount /dev/mapper/vg1-tmp /mnt/ec2-image/tmp
mount /dev/mapper/vg1-home /mnt/ec2-image/home
mount /dev/mapper/vg1-var /mnt/ec2-image/var
mkdir -p /mnt/ec2-image/var/log
mount /dev/mapper/vg1-var_log /mnt/ec2-image/var/log
mkdir -p /mnt/ec2-image/var/log/audit
mount /dev/mapper/vg1-var_log_audit /mnt/ec2-image/var/log/audit
mount /dev/xvdf1 /mnt/ec2-image/boot 
 
# make devices
mkdir -p /mnt/ec2-image/{dev,etc,proc,sys}
mkdir -p /mnt/ec2-image/var/{cache,log,lock,lib/rpm}
mknod -m 622 /mnt/ec2-image/dev/console c 5 1
mknod -m 666 /mnt/ec2-image/dev/null c 1 3
mknod -m 666 /mnt/ec2-image/dev/zero c 1 5
mknod -m 444 /mnt/ec2-image/dev/urandom c 1 9
mount -o bind /dev /mnt/ec2-image/dev
mount -o bind /dev/pts /mnt/ec2-image/dev/pts
mount -o bind /dev/shm /mnt/ec2-image/dev/shm
mount -o bind /proc /mnt/ec2-image/proc
mount -o bind /sys /mnt/ec2-image/sys

# selinux 
mount -t selinuxfs none /mnt/ec2-image/sys/fs/selinux
 
# create fstab 
cat <<EOF > /mnt/ec2-image/etc/fstab
/dev/mapper/vg1-root /                       xfs     defaults        0 0
LABEL=BOOTFS /boot                   xfs     defaults        0 0
/dev/mapper/vg1-home /home                   xfs     defaults        0 0
/dev/mapper/vg1-tmp  /tmp                    xfs     defaults        0 0
/dev/mapper/vg1-var  /var                    xfs     defaults        0 0
/dev/mapper/vg1-var_log /var/log                xfs     defaults        0 0
/dev/mapper/vg1-var_log_audit /var/log/audit          xfs     defaults        0 0
/dev/mapper/vg1-swap swap                    swap    defaults        0 0
EOF
 
# create a yum configuration for the installation 
mkdir -p /opt/ec2/yum
cat <<EOF> /opt/ec2/yum/yum.conf
[base]
name=Base
baseurl=http://mirror.centos.org/centos/7/os/x86_64/
gpgcheck=0
 
[updates]
name=Updates
baseurl=http://mirror.centos.org/centos/7/updates/x86_64/
gpgcheck=0
 
[extras]
name=Extras
baseurl=http://mirror.centos.org/centos/7/extras/x86_64/
gpgcheck=0
 
[puppetlabs-pc1]
name=Puppet Labs PC1 Repository el 7 
baseurl=http://yum.puppetlabs.com/el/7/PC1/x86_64/
gpgcheck=0
 
EOF

# Install the OS 
yum -c /opt/ec2/yum/yum.conf --installroot=/mnt/ec2-image -y install @core kernel openssh-clients grub2 grub2-tools lvm2 puppet-agent ipa-client scap-security-guide aide

# Install and Configure prov-client
yum -c /opt/ec2/yum/yum.conf --installroot=/mnt/ec2-image -y install /tmp/prov-client.rpm 
cat <<EOF > /mnt/ec2-image/etc/sysconfig/prov-client
SERVER=10.16.0.31
EOF

# Configure networking 
cat <<EOF > /mnt/ec2-image/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF
cat <<EOF > /mnt/ec2-image/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE="eth0"
NM_CONTROLLED="no"
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
PEERDNS=no
PEERROUTES=yes
IPV4_FAILURE_FATAL=yes
IPV6INIT=no
EOF
 
# Get console output at boot 
cat << EOF > /mnt/ec2-image/etc/default/grub
GRUB_TIMEOUT=1
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,115200n8 console=tty0"
GRUB_DISABLE_RECOVERY="true"
EOF
 
chroot /mnt/ec2-image grub2-install /dev/xvdf
chroot /mnt/ec2-image grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/ec2-image systemctl enable lvm2-lvmetad.service
chroot /mnt/ec2-image systemctl enable lvm2-lvmetad.socket
chroot /mnt/ec2-image fixfiles -f relabel
chroot /mnt/ec2-image oscap xccdf eval --remediate --profile xccdf_org.ssgproject.content_profile_stig-rhel7-server-upstream /usr/share/xml/scap/ssg/content/ssg-centos7-ds.xml
chroot /mnt/ec2-image echo "Banner /etc/issue" >> /etc/ssh/sshd_config
chroot /mnt/ec2-image echo "ClientAliveInterval 900" >> /etc/ssh/sshd_config
# scap turns off oddjobd; turn it back on
chroot /mnt/ec2-image systemctl enable oddjobd
chroot /mnt/ec2-image history -c
 
yum -c /opt/ec2/yum/yum.conf --installroot=/mnt/ec2-image -y clean all
umount /mnt/ec2-image/dev/shm
umount /mnt/ec2-image/dev/pts
umount /mnt/ec2-image/dev
umount /mnt/ec2-image/sys
umount /mnt/ec2-image/proc
umount /mnt/ec2-image/boot
umount /mnt/ec2-image/var/log/audit
umount /mnt/ec2-image/var/log
umount /mnt/ec2-image/tmp
umount /mnt/ec2-image/home
umount /mnt/ec2-image/var
umount /mnt/ec2-image
 