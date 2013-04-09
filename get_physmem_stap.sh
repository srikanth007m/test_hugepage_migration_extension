#!/bin/bash

usage() {
    echo "Usage: `basename $BASH_SOURCE` [-shv]"
    echo "  -s: show contents of Systemtap script before running"
    echo "  -h: show this message"
    echo "  -v: verbose"
    exit 1
}

SHOW=
VERBOSE=""
KEEPOPT=""
while getopts shv OPT
do
  case $OPT in
    "s" ) SHOW="on" ; KEEPOPT="-k" ;;
    "h" ) usage ;;
    "v" ) VERBOSE="--vp 11111" ;;
  esac
done
shift $[OPTIND-1]

stap=/usr/local/bin/stap

if ! grep "/sys/kernel/debug" /proc/mounts > /dev/null 2>&1 ; then
    mount -t debugfs none /sys/kernel/debug
fi
tmpf=`mktemp`

pb='printf("%28s %12s %5d %2d:", probefunc(), execname(), pid(), cpu())'

cat <<EOF > ${tmpf}.stp
#!/usr/bin/stap

%{
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/mm_types.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/hugetlb.h>
#include <linux/mmzone.h>
#include <linux/pageblock-flags.h>
#include "../../../arch/x86/include/asm/page.h"
#include "../../../arch/x86/include/asm/pgtable.h"
#include "../../../arch/x86/include/asm/pgtable_64.h"
#include "../../../arch/x86/include/asm/pgtable_types.h"

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
function ptr_deref:long (val:long) %{ STAP_RETVALUE = (long)*(long *)STAP_ARG_val; %}

function __pgd_offset:long (mm:long, addr:long) %{
    STAP_RETVALUE = (long)(pgd_offset((struct mm_struct *)STAP_ARG_mm, STAP_ARG_addr));
%}
function __pud_offset:long (pgd:long, addr:long) %{
    STAP_RETVALUE = (long)(pud_offset((pgd_t*)STAP_ARG_pgd, STAP_ARG_addr));
%}
function __pmd_offset:long (pud:long, addr:long) %{
    STAP_RETVALUE = (long)(pmd_offset((pud_t*)STAP_ARG_pud, STAP_ARG_addr));
%}
function __pte_offset:long (pmd:long, addr:long) %{
    STAP_RETVALUE = (long)(pte_offset_map((pmd_t*)STAP_ARG_pmd, STAP_ARG_addr));
%}
function __pgd_none:long (pgd:long) %{
    STAP_RETVALUE = (long)(pgd_none(*(pgd_t*)STAP_ARG_pgd));
%}
function __pud_none:long (pud:long) %{
    STAP_RETVALUE = (long)(pud_none(*(pud_t*)STAP_ARG_pud));
%}
function __pmd_none:long (pmd:long) %{
    STAP_RETVALUE = (long)(pmd_none(*(pmd_t*)STAP_ARG_pmd));
%}
function __pgd_bad:long (pgd:long) %{
    STAP_RETVALUE = (long)(pgd_bad(*(pgd_t*)STAP_ARG_pgd));
%}
function __pud_bad:long (pud:long) %{
    STAP_RETVALUE = (long)(pud_bad(*(pud_t*)STAP_ARG_pud));
%}
function __pmd_bad:long (pmd:long) %{
    STAP_RETVALUE = (long)(pmd_bad(*(pmd_t*)STAP_ARG_pmd));
%}
function __pte_present:long (pte:long) %{
    STAP_RETVALUE = (long)(pte_present(*(pte_t*)STAP_ARG_pte));
%}
function size_struct_page:long (val:long) %{
    STAP_RETVALUE = (long)(sizeof (struct page));
%}
EOF

echo_stp() { echo "$@" >> ${tmpf}.stp; }
while read name type deref ; do
    echo_stp "function ${name}:long (val:long) %{"
    echo_stp "    STAP_RETVALUE = (long)((struct ${type} *)STAP_ARG_val)${deref};"
    echo_stp "%}"
done <<EOF
page_flag     page        ->flags
page_private  page        ->private
task_mm       task_struct ->mm
EOF

SYM_node_data="0x$(egrep "\<node_data\>" /proc/kallsyms | cut -f1 -d' ')"
echo $SYM_node_data
cat <<EOF >> ${tmpf}.stp
# function nth_zone:long (n:long) %{
#     struct zone *zone = (first_online_pgdat())->node_zones;
#     int i = (int)STAP_ARG_n;
#     for (; i > 0; i--)
#         zone = next_zone(zone);
#     STAP_RETVALUE = (long)zone;
# %}
global node_data[10]
probe begin {
    ptr_node_data = $SYM_node_data;
    printf("&node_data %x\n", ptr_node_data);
    for (i = 0 ;; i++) {
        tmp = ptr_deref(ptr_node_data + 8*i);
        if (tmp) {
            node_data[i] = tmp;
        } else {
            break;
        }
    }
    foreach (nd in node_data) {
        printf("node_data[%d] %x\n", nd, node_data[nd]);
    }

    printf("size of struct page is %d\n", size_struct_page(1));

    exit();
}
EOF

[ "$SHOW" ] && less ${tmpf}.stp
$stap ${tmpf}.stp -g ${VERBOSE} -t ${KEEPOPT} -w --suppress-time-limits #-D MAXSKIPPED=

rm -f ${tmpf}*
