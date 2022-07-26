// PARAM: --enable ana.float.interval --enable ana.int.interval --enable ana.float.math_funeval
#include <assert.h>
#include <math.h>
#include <float.h>

int main()
{
    int x;
    double d;
    if (x) {
        d = -8.6;
    }
    else {
        d = -6.7;
    }
    assert(sin(d) < 0);
    assert(sin(d) > -0.99);
    assert(sin(d) < 0.99);
}
