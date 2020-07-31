#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/livepatch.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/version.h>

#include "expression.h"

MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("National Cheng Kung University, Taiwan");
MODULE_DESCRIPTION("Patch calc kernel module");
MODULE_VERSION("0.1");

void livepatch_nop_cleanup(struct expr_func *f, void *c)
{
    /* suppress compilation warnings */
    (void) f;
    (void) c;
}

int livepatch_nop(struct expr_func *f, vec_expr_t args, void *c)
{
    (void) args;
    (void) c;
    pr_err("function nop is now patched\n");
    return 0;
}

void livepatch_fib_cleanup(struct expr_func *f, void *c)
{
    /* suppress compilation warnings */
    (void) f;
    (void) c;
}

static int fib_sequence_fast_dobuling_clz(int k)
{
    int a = 0, b = FIXED_1;

    k = GET_NUM(k);
    if (!k)
        return 0;

    for (int i = ilog2(k); i >= 0; i--) {
        int t1, t2;

        t1 = a * ((b << 1) - a);
        t2 = b * b + a * a;

        /*
         * Reflect the 'correct' fixed-point value by dividing
         * FIXED_1 since the 't1' and 't2' calculation involves
         * multiplication operator.
         */
        a = t1 / FIXED_1;
        b = t2 / FIXED_1;

        if (k & (1ULL << i)) {
            t1 = a + b;
            a = b;
            b = t1;
        }
    }

    return a;
}

int livepatch_fib(struct expr_func *f, vec_expr_t args, void *c)
{
    struct expr *e = &args.buf[0];

    pr_err("function fib is now patched\n");

    if (!e) {
        printk("expr struct NULL\n");
        return -1;
    }

    if (e->type != OP_CONST) {
        printk("fib: argument is not a constant value!\n");
        return -1;
    }

    return fib_sequence_fast_dobuling_clz(e->param.num.value);
}

/* clang-format off */
static struct klp_func funcs[] = {
    {
        .old_name = "user_func_nop",
        .new_func = livepatch_nop,
    },
    {
        .old_name = "user_func_nop_cleanup",
        .new_func = livepatch_nop_cleanup,
    },
    {
        .old_name = "user_func_fib",
        .new_func = livepatch_fib,
    },
    {
        .old_name = "user_func_fib_cleanup",
        .new_func = livepatch_fib_cleanup,
    },
    {},
};
static struct klp_object objs[] = {
    {
        .name = "calc",
        .funcs = funcs,
    },
    {},
};
/* clang-format on */

static struct klp_patch patch = {
    .mod = THIS_MODULE,
    .objs = objs,
};

static int livepatch_calc_init(void)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)
    return klp_enable_patch(&patch);
#else
    int ret = klp_register_patch(&patch);
    if (ret)
        return ret;
    ret = klp_enable_patch(&patch);
    if (ret) {
        WARN_ON(klp_unregister_patch(&patch));
        return ret;
    }
    return 0;
#endif
}

static void livepatch_calc_exit(void)
{
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 1, 0)
    WARN_ON(klp_unregister_patch(&patch));
#endif
}

module_init(livepatch_calc_init);
module_exit(livepatch_calc_exit);
MODULE_INFO(livepatch, "Y");
