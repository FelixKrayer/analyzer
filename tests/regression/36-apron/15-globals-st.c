// SKIP PARAM: --set ana.activated[+] apron --set ana.path_sens[+] threadflag --disable ana.int.interval
#include <assert.h>

int g = 0;

int main(void) {
  int x, y, r;

  if (r) {
    g = 1;
  }

  // using apron interval
  assert(0 <= g);
  assert(g <= 1);

  g = r;

  x = g;
  y = g;
  assert(x == y);
  return 0;
}
