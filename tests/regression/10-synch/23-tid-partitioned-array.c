// PARAM: --set ana.activated[+] thread --set ana.base.arrays.domain partitioned
// NOCRASH
#include <pthread.h>

void *t_fun(void *arg) {
  return NULL;
}

int main(void) {
  pthread_t t_ids[10000];
  for (int i = 0; i < 10000; i++)
    pthread_create(&t_ids[i], NULL, t_fun, NULL);
  for (int i = 0; i < 10000; i++)
    pthread_join (t_ids[i], NULL);
  return 0;
}
