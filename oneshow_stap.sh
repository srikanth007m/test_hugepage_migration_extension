#!/bin/bash

usage() {
    echo "Usage: `basename $BASH_SOURCE` [-shv] pid"
    echo "  -s: show contents of Systemtap script"
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
[ $# -eq 0 ] && usage
PID=$1
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
function ptr_deref:long (val:long) %{ STAP_RETVALUE = (long)*(char *)STAP_ARG_val; %}

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

cat <<EOF >> ${tmpf}.stp
function get_addr:long (ipgd:long, ipud:long, ipmd:long, ipte:long) {
    return (ipgd << 39) + (ipud << 30) + (ipmd << 21) + (ipte << 12);
}

function nth_zone:long (n:long) %{
    struct zone *zone = (first_online_pgdat())->node_zones;
    int i = (int)STAP_ARG_n;
    for (; i > 0; i--)
        zone = next_zone(zone);
    STAP_RETVALUE = (long)zone;
%}

probe begin {
    for (i = 0; i < 3; i++) {
        printf("%d, zone %x\n", i, nth_zone(i));
    }
}

## global count
## probe begin {
##     task = pid2task(${PID});
##     mm = task_mm(task);
##     $pb ; printf(" task %p, mm %p\n", task, mm);
##     ipgd = 0; ipud = 0; ipmd = 0; ipte = 0;
##     for (ipgd = 0; ipgd < 512; ipgd++) {
##         ipud = 0; ipmd = 0; ipte = 0;
##         pgd = __pgd_offset(mm, get_addr(ipgd, ipud, ipmd, ipte));
##         if (pgd != NULL && !__pgd_none(pgd) && !__pgd_bad(pgd)) {
## #           $pb ; printf(" Q %x, %x, %x, %x, %x, %x, %x\n",
## #                        get_addr(ipgd, ipud, ipmd, ipte),
## #                        ipgd, ipud, ipmd, ipte, pgd, ptr_deref(pgd));
##           for (ipud = 0; ipud < 512; ipud++) {
##             ipmd = 0; ipte = 0;
##             pud = __pud_offset(pgd, get_addr(ipgd, ipud, ipmd, ipte));
##             if (pud != NULL && !__pud_none(pud) && !__pud_bad(pud)) {
## #               $pb ; printf(" R %x, %x, %x, %x, %x, %x, %x\n",
## #                          get_addr(ipgd, ipud, ipmd, ipte),
## #                          ipgd, ipud, ipmd, ipte, pud, ptr_deref(pud));
##               for (ipmd = 0; ipmd < 512; ipmd++) {
##                 ipte = 0;
##                 pmd = __pmd_offset(pud, get_addr(ipgd, ipud, ipmd, ipte));
##                 if (pmd != NULL && !__pmd_none(pmd) && !__pmd_bad(pmd)) {
##                   $pb ; printf(" S %x, %x, %x, %x, %x, %x, %x %x\n",
##                                get_addr(ipgd, ipud, ipmd, ipte),
##                                ipgd, ipud, ipmd, ipte, pmd, ptr_deref(pmd), __pmd_none(pmd));
##                   for (ipte = 0; ipte < 512; ipte++) {
##                     pte = __pte_offset(pmd, get_addr(ipgd, ipud, ipmd, ipte));
##                     if (__pte_present(pte)) {
##                       count += 1
## #                      $pb ; printf(" %x, %x, %x, %x, %x\n", ipgd, ipud, ipmd, ipte, get_addr(ipgd, ipud, ipmd, ipte));
##                     }
##                   }
##                 }
##               }
##             }
##           }
##         }
##     }
##     printf("count %x\n", count);
##     exit();
## }
EOF

[ "$SHOW" ] && less ${tmpf}.stp
$stap ${tmpf}.stp -g ${VERBOSE} -t ${KEEPOPT} -w --suppress-time-limits #-D MAXSKIPPED=

rm -f ${tmpf}*
