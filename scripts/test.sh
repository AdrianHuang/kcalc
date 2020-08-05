#!/usr/bin/env bash

CALC_DEV=/dev/calc
CALC_MOD=calc.ko
LIVEPATCH_CALC_MOD=livepatch-calc.ko

source scripts/eval.sh

wait_for_livepatch_calc_disabled() {
    local times=0 # 10-second waiting time
    while [ -d /sys/kernel/livepatch/livepatch_calc ]; do
        sleep 1
        times=$(($times+1))

        if [ $times -gt 10 ]; then
            break;
        fi
    done
}

test_op() {
    local expression=$1 
    local expect_ans
    local pass=0

    echo -n "Testing " ${expression} "..."

    echo -ne ${expression}'\0' > $CALC_DEV
    kcal_ans=`fromfixed $(cat $CALC_DEV)`

    if [ "$2" == "native_bash" ]; then
        expect_ans=$(($1))
    elif [ "$2" == "do_bc" ]; then
        expect_ans=$(echo "scale=7; $1" | bc -l)
    else
        expect_ans=$2
    fi

    if [ "$expect_ans" == "NAN_INT" ]; then
        [[ "$kcal_ans" == "$expect_ans" ]] && pass=1
    else
        [[ $(echo "$expect_ans == $kcal_ans" | bc) -eq 1 ]] && pass=1
    fi

    [[ $pass -eq 1 ]] && echo "PASS" || echo -e "FAIL (expect_ans: $expect_ans, kcal_ans=$kcal_ans)"
}

if [ "$EUID" -eq 0 ]
  then echo "Don't run this script as root"
  exit
fi

sudo rmmod -f livepatch-calc 2>/dev/null
sudo rmmod -f calc 2>/dev/null
sleep 1

modinfo $CALC_MOD || exit 1
sudo insmod $CALC_MOD
sudo chmod 0666 $CALC_DEV
echo

# multiply
test_op '6*7' 'native_bash'

# add
test_op '1980+1' 'native_bash'
# sub
test_op '2019-1' 'native_bash'

# div
test_op '42/6' 'native_bash'
test_op '1/3'  'do_bc'
test_op '1/3*6+2/4' 'do_bc'
test_op '(1/3)+(2/3)' 'do_bc'
test_op '(2145%31)+23' 'native_bash'
test_op '0/0' 'NAN_INT' # should be NAN_INT

# binary
test_op '(3%0)|0' '0' # should be 0
test_op '1+2<<3' 'native_bash' # should be (1 + 2) << 3 = 24
test_op '123&42' 'native_bash' # should be 42
test_op '123^42' 'native_bash' # should be 81

# parens
test_op '(((3)))*(1+(2))' 'native_bash' # should be 9

# assign
test_op 'x=5, x=(x!=0)' '1' # should be 1
test_op 'x=5, x = x+1' '6' # should be 6

# fancy variable name
test_op 'six=6, seven=7, six*seven' '42' # should be 42
test_op '小熊=6, 維尼=7, 小熊*維尼' '42' # should be 42
test_op 'τ=1.618, 3*τ' '4.854' # should be 3 * 1.618 = 4.854
test_op '$(τ, 1.618), 3*τ()' '4.854' # shold be 3 * 1.618 = 4.854

# functions
test_op '$(zero), zero()' '0' # should be 0
test_op '$(one, 1), one()+one(1)+one(1, 2, 4)' '3' # should be 3
test_op '$(number, 1), $(number, 2+3), number()' '5' # should be 5

# pre-defined function
test_op 'nop()' '0'
test_op 'fib(19)' '4181'

# Livepatch
sudo insmod $LIVEPATCH_CALC_MOD
sleep 1
echo "livepatch was applied"
test_op 'nop()' '0'
dmesg | tail -n 6
test_op 'fib(19)' '4181'
dmesg | tail -n 6
echo "Disabling livepatch..."
sudo sh -c "echo 0 > /sys/kernel/livepatch/livepatch_calc/enabled"
wait_for_livepatch_calc_disabled

sudo rmmod livepatch-calc
sudo rmmod calc

# epilogue
echo "Complete"
