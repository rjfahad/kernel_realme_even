### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Arise Even Kernel by rjfahad
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=RMX3191
device.name2=RMX3193
device.name3=RMX3194
device.name4=RMX3195
device.name5=RMX3197
device.name6=oppo6769_2167A
device.name7=Even
device.name8=even
device.name9=oppo6769
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

ui_print " "
ui_print "    ###    ######   #######   ######  #######"
ui_print "   #   #   #     #     #     #        #      "
ui_print "  #     #  #     #     #     #        #      "
ui_print "  #######  ######      #      #####   #####  "
ui_print "  #     #  #   #       #           #  #      "
ui_print "  #     #  #    #      #           #  #      "
ui_print "  #     #  #     #  #######  ######   #######"
ui_print " "
ui_print "      Arise Even Kernel (MT6768)"
ui_print " "
# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

# end ramdisk changes

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
## end boot install
