#!/bin/bash

usage() {
    echo "Usage: `basename $BASH_SOURCE` [-shv]"
    echo "  -s: show contents of Systemtap script"
    echo "  -h: show this message"
    echo "  -v: verbose"
    exit 1
}

show=
VERBOSE=""
while getopts shv OPT
do
  case $OPT in
    "s" ) show="on" ;;
    "h" ) usage ;;
    "v" ) VERBOSE="--vp 11111" ;;
  esac
done

stap=/usr/local/bin/stap

if ! grep "/sys/kernel/debug" /proc/mounts > /dev/null 2>&1 ; then
    mount -t debugfs none /sys/kernel/debug
fi

tmpf=`mktemp`

pb='printf("%28s %12s %5d %2d %d:", probefunc(), execname(), pid(), cpu(), gettimeofday_us())'
pb='printf("%28s %12s %5d %2d:", probefunc(), execname(), pid(), cpu())'

# mapping between function's arguments and registeres
# %rdi, %rsi, %rdx, %rcx, %r8, %r9

cat <<EOF > ${tmpf}.stp
#!/usr/bin/stap

%{
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/fs.h>
#include <linux/hugetlb.h>
#include <linux/mmzone.h>
#include <linux/pageblock-flags.h>
#include <linux/memory.h>

unsigned long __call_kernel_func1(unsigned long func, unsigned long arg1)
{
        char *(*f)(unsigned long) = (char *(*)(unsigned long))func;
        return (unsigned long)f(arg1);
}
unsigned long __call_kernel_func2(unsigned long func, unsigned long arg1, unsigned long arg2)
{
        char *(*f)(unsigned long, unsigned long) = (char *(*)(unsigned long, unsigned long))func;
        return (unsigned long)f(arg1, arg2);
}
unsigned long __call_kernel_func3(unsigned long func, unsigned long arg1, unsigned long arg2, unsigned long arg3)
{
        char *(*f)(unsigned long, unsigned long, unsigned long) = (char *(*)(unsigned long, unsigned long, unsigned long))func;
        return (unsigned long)f(arg1, arg2, arg3);
}
unsigned long __call_kernel_func4(unsigned long func, unsigned long arg1, unsigned long arg2, unsigned long arg3, unsigned long arg4)
{
        char *(*f)(unsigned long, unsigned long, unsigned long, unsigned long) = (char *(*)(unsigned long, unsigned long, unsigned long, unsigned long))func;
        return (unsigned long)f(arg1, arg2, arg3, arg4);
}
unsigned long __call_kernel_func5(unsigned long func, unsigned long arg1, unsigned long arg2, unsigned long arg3, unsigned long arg4, unsigned long arg5)
{
        char *(*f)(unsigned long, unsigned long, unsigned long, unsigned long, unsigned long) = (char *(*)(unsigned long, unsigned long, unsigned long, unsigned long, unsigned long))func;
        return (unsigned long)f(arg1, arg2, arg3, arg4, arg5);
}
unsigned long __call_kernel_func6(unsigned long func, unsigned long arg1, unsigned long arg2, unsigned long arg3, unsigned long arg4, unsigned long arg5, unsigned long arg6)
{
        char *(*f)(unsigned long, unsigned long, unsigned long, unsigned long, unsigned long, unsigned long) = (char *(*)(unsigned long, unsigned long, unsigned long, unsigned long, unsigned long, unsigned long))func;
        return (unsigned long)f(arg1, arg2, arg3, arg4, arg5, arg6);
}
%}
function call_kernel_func1:long (func:long, a1:long) %{ STAP_RETVALUE = (long)__call_kernel_func1(STAP_ARG_func, STAP_ARG_a1); %}
function call_kernel_func2:long (func:long, a1:long, a2:long) %{ STAP_RETVALUE = (long)__call_kernel_func2(STAP_ARG_func, STAP_ARG_a1, STAP_ARG_a2); %}
function call_kernel_func3:long (func:long, a1:long, a2:long, a3:long) %{ STAP_RETVALUE = (long)__call_kernel_func3(STAP_ARG_func, STAP_ARG_a1, STAP_ARG_a2, STAP_ARG_a3); %}
function call_kernel_func4:long (func:long, a1:long, a2:long, a3:long, a4:long) %{ STAP_RETVALUE = (long)__call_kernel_func4(STAP_ARG_func, STAP_ARG_a1, STAP_ARG_a2, STAP_ARG_a3, STAP_ARG_a4); %}
function call_kernel_func5:long (func:long, a1:long, a2:long, a3:long, a4:long, a5:long) %{ STAP_RETVALUE = (long)__call_kernel_func5(STAP_ARG_func, STAP_ARG_a1, STAP_ARG_a2, STAP_ARG_a3, STAP_ARG_a4, STAP_ARG_a5); %}
function call_kernel_func6:long (func:long, a1:long, a2:long, a3:long, a4:long, a5:long, a6:long) %{ STAP_RETVALUE = (long)__call_kernel_func6(STAP_ARG_func, STAP_ARG_a1, STAP_ARG_a2, STAP_ARG_a3, STAP_ARG_a4, STAP_ARG_a5, STAP_ARG_a6); %}
function arg1:long () { return register("rdi"); }
function arg2:long () { return register("rsi"); }
function arg3:long () { return register("rdx"); }
function arg4:long () { return register("rcx"); }
function arg5:long () { return register("r8"); }
function arg6:long () { return register("r9"); }

function pfn_to_page:long (val:long) %{ STAP_RETVALUE = (long)pfn_to_page((unsigned long)STAP_ARG_val); %}
function page_to_pfn:long (val:long) %{ STAP_RETVALUE = (long)page_to_pfn((struct page *)STAP_ARG_val); %}
function page_count:long (val:long) %{ STAP_RETVALUE = (long)page_count((struct page *)STAP_ARG_val); %}
function page_mapcount:long (val:long) %{ STAP_RETVALUE = (long)page_mapcount((struct page *)STAP_ARG_val); %}
function ptr_deref:long (val:long) %{ STAP_RETVALUE = (long)*(char *)STAP_ARG_val; %}

function migtype:long (val:long) %{
    STAP_RETVALUE = MIGRATE_TYPES;
%}

function get_migratetype:long (val:long) %{
    unsigned long flags = 0;
    struct page *page = (struct page *)STAP_ARG_val;
    struct zone *zone = page_zone(page);
    unsigned long pfn = page_to_pfn(page);
    unsigned long *bitmap = __pfn_to_section(pfn)->pageblock_flags;
    unsigned long bitidx = ((pfn & (PAGES_PER_SECTION-1)) >> 15) * NR_PAGEBLOCK_BITS;

    int i;
    for (i = 0; i < 3; i++)
            if (test_bit(bitidx + i, bitmap))
                    flags |= 1<<i;
    STAP_RETVALUE = flags;
%}
EOF

echo_stp() { echo "$@" >> ${tmpf}.stp; }
while read name type deref ; do
    echo_stp "function ${name}:long (val:long) %{"
    echo_stp "    STAP_RETVALUE = (long)((struct ${type} *)STAP_ARG_val)${deref};"
    echo_stp "%}"
done <<EOF
page_flag     page       ->flags
EOF

getsymaddr() {
    grep $1 /proc/kallsyms | awk '{print $1}'
}

cat <<EOF >> ${tmpf}.stp
probe begin {
}

probe kernel.function("free_one_page") {
    pfn = page_to_pfn(arg2());
    $pb; printf(" pfn:%x, migtype:%x\n", pfn, arg4());
}

# probe kernel.function("start_isolate_page_range") {
#     i = \$start_pfn;
#     j = \$end_pfn;
#     start = pfn_to_page(\$start_pfn);
#     end   = pfn_to_page(\$end_pfn);
# #     printf("-------------- %s\n", probefunc());
# #     for (; i < j; i += 512) {
# #         ipage = pfn_to_page(i);
# #         printf(" %x:%x/016%x, %x:%x/%016x, %x:%x/%016x\n", i, get_migratetype(ipage), page_flag(ipage), i+1, get_migratetype(ipage+1), page_flag(ipage+1), i-1, get_migratetype(ipage-1), page_flag(ipage-1));
# #     }
# }

# # probe kernel.function("start_isolate_page_range") {
# #     $pb; printf(" arg1 %x, arg2 %x\n", arg1(), arg2());
# # }
# # 
# probe kernel.function("start_isolate_page_range").return {
#     i = \$start_pfn;
#     j = \$end_pfn;
#     start = pfn_to_page(\$start_pfn);
#     end   = pfn_to_page(\$end_pfn);
# #     printf("-------------- %s (%x)\n", probefunc(), returnval());
# #     for (; i < j; i += 512) {
# #         ipage = pfn_to_page(i);
# #         printf(" %x:%x/016%x, %x:%x/%016x, %x:%x/%016x\n", i, get_migratetype(ipage), page_flag(ipage), i+1, get_migratetype(ipage+1), page_flag(ipage+1), i-1, get_migratetype(ipage-1), page_flag(ipage-1));
# #     }
# }
# 
# probe kernel.function("has_unmovable_pages").return {
#     pfn = page_to_pfn(\$page);
# #     printf("has_unmovable_pages pfn:%x, %x\n", pfn, returnval());
# #     if (returnval() > 0) {
# #         for (i = 0; i < 512; i++) {
# #             tmppage = pfn_to_page(pfn + i);
# #             printf("  pfn %x, flag %016x\n", pfn + i, page_flag(tmppage));
# #         }
# #     }
# }
# 
# # probe kernel.function("memory_isolate_notify").return {
# #     printf("memory_isolate_notify val:%x, %x\n", \$val, returnval());
# # }
EOF

[ "$show" ] && less ${tmpf}.stp
$stap ${tmpf}.stp -g ${VERBOSE} -t -w # --suppress-time-limits #-D MAXSKIPPED=

rm -f ${tmpf}*
