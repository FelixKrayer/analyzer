  $ cfgDot 20-if-0-realnode.c | graph-easy --as=boxart
  ┌──────────────────────────────────┐
  │      __goblint_dummy_init()      │
  └──────────────────────────────────┘
    │
    │ return
    ▼
  ┌──────────────────────────────────┐
  │ return of __goblint_dummy_init() │
  └──────────────────────────────────┘
  ┌──────────────────────────────────┐
  │              main()              │
  └──────────────────────────────────┘
    │
    │ (body)
    ▼
  ┌──────────────────────────────────┐   Neg(0)
  │   20-if-0-realnode.c:8:9-8:10    │ ─────────┐
  │        (synthetic: false)        │          │
  │                                  │ ◀────────┘
  └──────────────────────────────────┘
    │
    │ Pos(0)
    ▼
  ┌──────────────────────────────────┐
  │  20-if-0-realnode.c:10:9-10:16   │
  │        (synthetic: false)        │
  └──────────────────────────────────┘
    │
    │ stuff()
    ▼
  ┌──────────────────────────────────┐
  │  20-if-0-realnode.c:15:5-15:13   │
  │        (synthetic: false)        │
  └──────────────────────────────────┘
    │
    │ return 0
    ▼
  ┌──────────────────────────────────┐
  │         return of main()         │
  └──────────────────────────────────┘
  ┌──────────────────────────────────┐
  │             stuff()              │
  └──────────────────────────────────┘
    │
    │ (body)
    ▼
  ┌──────────────────────────────────┐
  │    20-if-0-realnode.c:3:1-3:1    │
  │        (synthetic: false)        │
  └──────────────────────────────────┘
    │
    │ return
    ▼
  ┌──────────────────────────────────┐
  │        return of stuff()         │
  └──────────────────────────────────┘
