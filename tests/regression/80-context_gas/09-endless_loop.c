// PARAM: --enable ana.int.interval_set --set ana.context.gas_value 10
// Without context-insensitive analysis: endless loop
#include <stdio.h>

int num_iterat = 2;

int main(void)
{
    if (num_iterat > 0)
    {
        num_iterat++;
        int res = main();
        __goblint_check(res == 5); // UNKNOWN
        return res;
    }
    else
    {
        if (num_iterat == 0)
        {
            return 5;
        }
        return 2;
    }
}
