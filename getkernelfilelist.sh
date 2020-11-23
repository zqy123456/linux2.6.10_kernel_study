#!/bin/bash
#
# Author: Calvin
#
# Function: Create a list of active file of compiled linux kernel.
#           Create a macros condition file from autoconf.h
#
# 2020/03/30 - Support build kernel out of source tree.
# 2020/04/01 - Add dependent .S files. Some .S include other source files.

usage()
{
    cat << EOF
    Usage: getkernelfilelist.sh <src-path> [arch]
EOF
}

path=$(cd $1 && pwd)
output_path=$PWD

# change_prefix file_name orignal_prefix target_prefix
# For those files without the given orignal_prefix, leave unchanged
change_prefix()
{
    [[ $1 =~ ${2}.* ]] && echo $1 | sed -e "s,${2},${3},"
}

ARCH=$2
[ -n "$ARCH" ] || ARCH=x86
mach=$(sed -n -e "s,CONFIG_SYS_SOC=\"\(.*\)\",\1,p" .config)
#echo "mach is ${mach}"

objects=$(find $output_path -name "*.o" ! -path "$output_path/.git/*" ! -path "$output_path/scripts/*" ! -path "$output_path/tools/*")
for obj in $objects; do
    obj=$(echo $obj | sed -e "s,${output_path}/spl/\(.*\),${output_path}/\1,g")
    tmp_obj=$(change_prefix $obj $output_path $path)
    [ -f "${tmp_obj%.o}.c" ] && source="${tmp_obj%.o}.c"
    [ -f "${tmp_obj%.o}.S" ] && source="${tmp_obj%.o}.S"
    [ -f "$source" ] || continue
    sources="$sources $source"
    cmdfile="${obj%/*}/.${obj##*/}.cmd"
    [ -f "$cmdfile" ] || continue
    deps=$(grep -o -e "${path}/[-a-z_A-Z0-9/.]*\.[hcsS]\>" -e "include/asm/arch/.*\.h" $cmdfile | sed -e "s,include/asm/arch/,${path}/arch/$ARCH/include/asm/arch-${mach}/,g")
    #if echo $cmdfile | grep -e 'include\/asm\/arch\/' ; then
    #    echo $deps
    #    exit
    #fi
    total_deps=$(echo $total_deps $deps | tr '[:blank:]' '\n' | sort -n | uniq)
done
#total_deps=$(echo $total_deps | tr '[:blank:]' '\n' | grep -v 'include/config')
for h in $total_deps; do
    [ -f $h ] && kernel_header="${kernel_header} $h"
done
rm -f kernelfilelist.txt
#sources=$(echo $sources | tr '[:blank:]' '\n' | sed -e 's,\./\(.*\)$,\1 ,g')
echo $sources $kernel_header | tr '[:blank:]' '\n' | sort -n | uniq | xargs -I {} readlink -f {} | sort -n | uniq >>kernelfilelist.txt
sed -e "s,${path}/\(.*\),\1,g"  -i kernelfilelist.txt

# create configs xml.
rm -f kernel.conditions.xml
cat >kernel.conditions.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<SourceInsightParseConditions
    AppVer="4.00.0084"
    AppVerMinReader="4.00.0019"
    >
    <ParseConditions>
        <Defines>
EOF


grep define $output_path/include/generated/autoconf.h | \
while read keyword confid value; do
    value=$(echo $value | sed -e 's,",,g')
    printf "            <define id=\"$confid\" value=\"$value\" />\n"
done >>kernel.conditions.xml

allconfig=$(find $path/arch/$ARCH -maxdepth 1 ! -path "./Documentation/*" -name 'Kconfig*' | xargs grep -P "^\s*(menu)?config [A-Z_0-9]"  | awk '{print $NF}')
allconfig="$allconfig $(find . -maxdepth 2 ! -path "./Documentation/*" -name 'Kconfig*' | xargs grep -P '^\s*(menu)?config [A-Z_0-9]' | awk '{print $NF}')"
for conf in $allconfig; do
    confid="CONFIG_$conf"
    if ! grep -e "\<$confid\>" $output_path/include/generated/autoconf.h >/dev/null; then
        printf "            <define id=\"$confid\" value=\"0\" />\n"
    fi
done >>kernel.conditions.xml

cat >>kernel.conditions.xml << EOF
        </Defines>
    </ParseConditions>
</SourceInsightParseConditions>
EOF

echo finished!

exit

